"""Phase 1 eval: run the reviewer prompt + schema on real lecture PDFs and score the output.

It uses the SAME prompt and schema files as the app (assets/prompts/, ADR-006),
calls Gemini through Vertex AI / Agent Platform (so Cloud credits apply and
lecture files are not used for training), and scores each deck on:

  validity    items that follow the per-type rules (same rules the app's parser enforces)
  grounding   answers that can actually be found in the PDF text
  mix         how close the question-type mix is to the target in the prompt
  uniqueness  no near-duplicate questions
  language    explanations written in the requested language (simple word-list heuristic)

Score per deck = average of the five, as a percentage. Phase 1 goal: >= 80%.

Usage (run from the evals/ folder):
  uv run run_eval.py --model gemini-3.8-flash
  uv run run_eval.py --model gemini-3.5-flash-lite --only LECT4
  uv run run_eval.py --model gemini-3.8-flash --rescore   # re-score cached answers, no API calls

Responses are cached in results/raw/ (keyed by prompt + schema + PDF + settings),
so re-running after changing only the scoring code costs nothing.
Sign-in: uses your gcloud Application Default Credentials.
"""

import argparse
import hashlib
import json
import re
import time
import unicodedata
from collections import Counter
from datetime import datetime
from pathlib import Path

from google import genai
from google.genai import types
from jsonschema import Draft202012Validator
from pypdf import PdfReader
from rapidfuzz import fuzz

# ---------------------------------------------------------------- settings
PROJECT = "study-buddy-ffd63"
LOCATION = "global"

ROOT = Path(__file__).resolve().parent.parent
PROMPT_FILE = ROOT / "assets" / "prompts" / "generate_reviewer.md"
SCHEMA_FILE = ROOT / "assets" / "prompts" / "reviewer_schema.json"
LECTURES_DIR = Path(__file__).resolve().parent / "lectures"
RESULTS_DIR = Path(__file__).resolve().parent / "results"

# Big enough that a 40-question deck plus thinking never gets cut off.
# We record real usage here to pick the app's maxOutputTokens later.
MAX_OUTPUT_TOKENS = 32768

MIX_FILE = ROOT / "assets" / "prompts" / "question_mix.json"
QUIZ_TYPES = ["multiple_choice", "identification", "modified_true_false", "enumeration", "true_false"]


def base_mix() -> dict[str, float]:
    """Base type shares, shared with the app (ADR-008)."""
    raw = json.loads(MIX_FILE.read_text(encoding="utf-8"))
    return {k: float(v) for k, v in raw.items() if not k.startswith("_")}


def target_mix(question_types: list[str]) -> dict[str, float]:
    """Keep only the chosen types and re-scale to 1 (same as GenerationOptions.targetMix)."""
    picked = {t: s for t, s in base_mix().items() if t in question_types}
    total = sum(picked.values())
    return {t: s / total for t, s in picked.items()} if total else {}


def fill_prompt(template: str, language: str, question_types: list[str], notes: bool, page_count: int) -> str:
    """Exactly what fillPromptTemplate() in lib/services/generator_service.dart does."""
    mix = target_mix(question_types)
    if mix:
        rows = ["| type | share |", "|---|---|"]
        for t, share in mix.items():
            extra = " (only if the PDF has real lists)" if t == "enumeration" else ""
            rows.append(f"| {t} | {int(share * 100 + 0.5)}%{extra} |")  # Dart's round(): half away from 0
        table = "\n".join(rows)
    else:
        table = "(No questions requested.)"
    notes_text = ("requested. Write key points by topic (section 5)." if notes
                  else "not requested. Set `notes` to an empty list.")
    n_questions = target_questions(page_count) if question_types else 0
    return (template
            .replace("{{explanation_language}}", language)
            .replace("{{target_questions}}", str(n_questions))
            .replace("{{question_mix}}", table)
            .replace("{{notes_instruction}}", notes_text))

# USD per 1M tokens (input, output incl. thinking). Source: Gemini API pricing
# page, checked 2026-11-20 (Agent Platform page didn't load; confirm in console).
PRICES = {
    "gemini-3.8-flash": (0.75, 3.75),
    "gemini-3.5-flash-lite": (0.30, 2.50),
}

# Common Filipino function words, for the explanation-language check.
FILIPINO_WORDS = {
    "ang", "ng", "mga", "sa", "na", "ay", "kasi", "yung", "ito", "iyon", "hindi",
    "para", "siya", "nito", "dahil", "lang", "din", "rin", "kung", "naman", "po",
    # No "to" ('to = ito): it's also one of the most common English words.
    "natin", "nila", "niya", "yan", "ni", "nang", "ba", "pa", "kaya", "dapat",
    "lahat", "mas", "pag", "kapag", "ganito", "tayo", "ka", "mo", "ko", "sila",
}


def target_questions(page_count: int) -> int:
    """About 0.8 questions per page, between 10 and 40."""
    return min(40, max(10, round(page_count * 0.8)))


# ---------------------------------------------------------------- text helpers
def normalize(text: str) -> str:
    """Lowercase, remove accents and punctuation, collapse spaces."""
    text = unicodedata.normalize("NFKD", text or "")
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = re.sub(r"[^a-z0-9]+", " ", text.lower())
    return " ".join(text.split())


def read_pdf_pages(path: Path) -> list[str]:
    return [normalize(page.extract_text() or "") for page in PdfReader(path).pages]


def find_in_pdf(phrase: str, pages: list[str], threshold: int) -> int | None:
    """Return the 1-based page where `phrase` fuzzily appears, or None."""
    needle = normalize(phrase)
    if not needle:
        return None
    best_page, best_score = None, 0.0
    for i, page in enumerate(pages, start=1):
        if not page:
            continue
        score = 100.0 if needle in page else fuzz.partial_ratio(needle, page)
        if score > best_score:
            best_page, best_score = i, score
    return best_page if best_score >= threshold else None


# ---------------------------------------------------------------- per-item rules
def item_problems(q: dict, page_count: int) -> list[str]:
    """Per-type rules. The Dart parser will drop items that break these."""
    problems = []
    kind = q.get("type")
    for field in ("prompt", "answer", "explanation"):
        if not str(q.get(field, "")).strip():
            problems.append(f"empty {field}")
    page = q.get("source_page")
    if not isinstance(page, int) or not 1 <= page <= page_count:
        problems.append(f"source_page {page} outside 1..{page_count}")

    if kind == "multiple_choice":
        choices = q.get("choices") or []
        if len(choices) != 4:
            problems.append(f"{len(choices)} choices")
        if q.get("answer") not in choices:
            problems.append("answer not in choices")
        if len({normalize(c) for c in choices}) != len(choices):
            problems.append("duplicate choices")
    elif kind == "enumeration":
        if len(q.get("items") or []) < 2:
            problems.append("fewer than 2 items")
    elif kind in ("true_false", "modified_true_false"):
        if q.get("answer") not in ("True", "False"):
            problems.append(f"answer {q.get('answer')!r} is not True/False")
    if kind == "modified_true_false":
        underlined = q.get("underlined_word", "")
        # Case-insensitive: the app can underline "Spur" inside "spur" just fine.
        if not underlined or underlined.lower() not in q.get("prompt", "").lower():
            problems.append("underlined_word not in prompt")
        if q.get("answer") == "False":
            correction = q.get("correction", "")
            if not correction.strip():
                problems.append("False but no correction")
            elif normalize(correction) == normalize(underlined):
                problems.append("correction same as underlined_word")
        elif q.get("answer") == "True" and normalize(q.get("correction", "")) not in ("", normalize(underlined)):
            problems.append("True but correction differs from underlined_word")
    if kind == "identification":
        answer = normalize(q.get("answer", ""))
        if answer and re.search(rf"\b{re.escape(answer)}\b", normalize(q.get("prompt", ""))):
            problems.append("answer appears in prompt")
    return problems


def grounding_targets(q: dict) -> list[list[str]] | None:
    """Phrases that must be in the PDF. Each inner list = 'any of these'.
    None = this item can't be checked by text search (e.g. true/false statements)."""
    kind = q.get("type")
    if kind == "identification":
        return [[q["answer"], *(q.get("accepted_answers") or [])]]
    if kind == "multiple_choice":
        return [[q["answer"]]]
    if kind == "flashcard":
        # The front may be a question, so check either side; the back is often
        # the PDF's own wording.
        return [[q["prompt"], q["answer"]]]
    if kind == "enumeration":
        return [[item] for item in q.get("items") or []]
    if kind == "modified_true_false":
        key = q.get("correction") if q.get("answer") == "False" else q.get("underlined_word")
        return [[key or ""]]
    return None


def check_grounding(q: dict, pages: list[str]) -> tuple[bool | None, bool | None]:
    """(answer found in PDF?, found near source_page?) or (None, None) if not checkable."""
    targets = grounding_targets(q)
    if not targets:
        return None, None
    found_pages = []
    for alternatives in targets:
        hits = [find_in_pdf(a, pages, threshold=85) for a in alternatives]
        found_pages.append(next((h for h in hits if h), None))
    found = sum(p is not None for p in found_pages) / len(found_pages) >= 0.75
    near = any(p is not None and abs(p - q.get("source_page", -99)) <= 1 for p in found_pages)
    return found, near


def explanation_language_ok(text: str, expected: str) -> bool:
    words = normalize(text).split()
    if not words:
        return False
    ratio = sum(w in FILIPINO_WORDS for w in words) / len(words)
    if expected == "english":
        return ratio < 0.05
    if expected == "filipino":
        return ratio >= 0.20
    return 0.08 <= ratio <= 0.60  # taglish: clearly some Filipino, clearly some English


def near_duplicates(questions: list[dict]) -> int:
    prompts = [normalize(q.get("prompt", "")) for q in questions]
    dupes = 0
    for i in range(len(prompts)):
        # token_sort_ratio compares the whole wording; token_set_ratio wrongly gave 100
        # when a one-word flashcard ("VIRTUE") was contained in a longer question.
        if any(fuzz.token_sort_ratio(prompts[i], prompts[j]) >= 90 for j in range(i)):
            dupes += 1
    return dupes


# ---------------------------------------------------------------- scoring
def score_notes(notes: list, pages: list[str], language: str) -> tuple[float, dict]:
    """Notes: valid sections, headings found in the PDF, points in the right language."""
    if not notes:
        return 0.0, {"note_sections": 0}
    valid = [s for s in notes
             if str(s.get("heading", "")).strip() and s.get("points")
             and isinstance(s.get("source_page"), int) and 1 <= s["source_page"] <= len(pages)]
    headings_found = sum(find_in_pdf(s["heading"], pages, threshold=80) is not None for s in valid)
    points = [p for s in valid for p in s["points"]]
    lang_ok = sum(explanation_language_ok(p, language) for p in points)
    parts = [
        len(valid) / len(notes),
        headings_found / len(valid) if valid else 0.0,
        lang_ok / len(points) if points else 0.0,
    ]
    return sum(parts) / len(parts), {
        "note_sections": len(notes),
        "note_headings_found": f"{headings_found}/{len(valid)}",
        "note_points": len(points),
    }


def score_deck(deck: dict, pages: list[str], language: str, schema: dict,
               question_types: list[str], notes_wanted: bool) -> dict:
    schema_errors = [e.message for e in Draft202012Validator(schema).iter_errors(deck)]
    questions = deck.get("questions") or []
    notes = deck.get("notes") or []
    n = len(questions)

    extra = {}
    if notes_wanted:
        notes_part, extra = score_notes(notes, pages, language)
    else:
        notes_part = 1.0 if not notes else 0.0  # asked for none, got none

    if not question_types:  # notes-only deck
        parts = {"validity": 1.0 if not questions else 0.0, "notes": notes_part}
        return {"score": round(100 * sum(parts.values()) / len(parts), 1),
                **{k: round(100 * v, 1) for k, v in parts.items()},
                "questions": n, "schema_errors": schema_errors[:5], **extra}
    if not n:
        return {"score": 0.0, "questions": 0, "schema_errors": schema_errors[:5], **extra}

    problems = {i: item_problems(q, len(pages)) for i, q in enumerate(questions)}
    for i, q in enumerate(questions):
        if q.get("type") not in question_types:
            problems[i].append("type not requested")
    valid = [q for i, q in enumerate(questions) if not problems[i]]

    grounded = checkable = near_page = 0
    ungrounded_examples = []
    for q in valid:
        found, near = check_grounding(q, pages)
        if found is None:
            continue
        checkable += 1
        grounded += bool(found)
        near_page += bool(near)
        if not found and len(ungrounded_examples) < 5:
            ungrounded_examples.append(f"[{q['type']}] {q['prompt'][:70]} -> {q['answer'][:50]}")

    counts = Counter(q.get("type") for q in questions)
    wanted = target_mix(question_types)
    mix = 1 - 0.5 * sum(abs(counts.get(t, 0) / n - wanted.get(t, 0.0)) for t in set(wanted) | set(counts))
    dupes = near_duplicates(questions)
    lang_ok = sum(explanation_language_ok(q.get("explanation", ""), language) for q in valid)

    parts = {
        "validity": len(valid) / n,
        "grounding": grounded / checkable if checkable else 0.0,
        "mix": max(mix, 0.0),
        "uniqueness": 1 - dupes / n,
        "language": lang_ok / len(valid) if valid else 0.0,
        "notes": notes_part,
    }
    return {
        "score": round(100 * sum(parts.values()) / len(parts), 1),
        **{k: round(100 * v, 1) for k, v in parts.items()},
        **extra,
        "questions": n,
        "valid": len(valid),
        "type_counts": dict(counts),
        "page_accuracy": round(100 * near_page / checkable, 1) if checkable else None,
        "duplicates": dupes,
        "schema_errors": schema_errors[:5],
        "item_problems": Counter(p for ps in problems.values() for p in ps).most_common(8),
        "ungrounded_examples": ungrounded_examples,
    }


# ---------------------------------------------------------------- Gemini call (cached)
def generate(client, model: str, pdf_path: Path, prompt: str, schema: dict,
             cache_key: str, rescore: bool) -> dict:
    cache_file = RESULTS_DIR / "raw" / model / f"{pdf_path.stem[:40]}__{cache_key[:10]}.json"
    if cache_file.exists():
        return json.loads(cache_file.read_text(encoding="utf-8"))
    if rescore:
        return {"error": "no cached response (run without --rescore)"}

    started = time.time()
    response = None
    for attempt in range(4):  # retry rate limits (429) and overload (503) with backoff
        try:
            response = client.models.generate_content(
                model=model,
                contents=[
                    types.Part.from_bytes(data=pdf_path.read_bytes(), mime_type="application/pdf"),
                    prompt,
                ],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_json_schema=schema,
                    max_output_tokens=MAX_OUTPUT_TOKENS,
                ),
            )
            break
        except Exception as e:  # one bad PDF shouldn't stop the whole run
            retryable = any(code in str(e) for code in ("429", "503", "RESOURCE_EXHAUSTED", "UNAVAILABLE"))
            if not retryable or attempt == 3:
                return {"error": f"{type(e).__name__}: {e}"[:500]}
            wait = 30 * (attempt + 1)
            print(f"    rate-limited, retrying in {wait}s", flush=True)
            time.sleep(wait)

    usage = response.usage_metadata
    candidate = (response.candidates or [None])[0]
    result = {
        "text": response.text,
        "finish_reason": str(getattr(candidate, "finish_reason", None)),
        "seconds": round(time.time() - started, 1),
        "input_tokens": usage.prompt_token_count or 0,
        "output_tokens": usage.candidates_token_count or 0,
        "thinking_tokens": usage.thoughts_token_count or 0,
    }
    cache_file.parent.mkdir(parents=True, exist_ok=True)
    cache_file.write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", default="gemini-3.8-flash")
    parser.add_argument("--language", default="english", choices=["english", "filipino", "taglish"])
    parser.add_argument("--only", help="only PDFs whose name contains this text")
    parser.add_argument("--rescore", action="store_true", help="score cached responses only, no API calls")
    parser.add_argument("--quiz-types", default=",".join(QUIZ_TYPES),
                        help="comma list of quiz types, or 'none' (default: all 5)")
    parser.add_argument("--no-flashcards", action="store_true")
    parser.add_argument("--no-notes", action="store_true")
    args = parser.parse_args()
    quiz = [] if args.quiz_types == "none" else [t.strip() for t in args.quiz_types.split(",") if t.strip()]
    question_types = quiz + ([] if args.no_flashcards else ["flashcard"])
    notes_wanted = not args.no_notes

    prompt_template = PROMPT_FILE.read_text(encoding="utf-8")
    schema_text = SCHEMA_FILE.read_text(encoding="utf-8")
    schema = json.loads(schema_text)
    client = genai.Client(vertexai=True, project=PROJECT, location=LOCATION)
    price_in, price_out = PRICES.get(args.model, (0.0, 0.0))

    pdfs = sorted(p for p in LECTURES_DIR.glob("*.pdf") if not args.only or args.only.lower() in p.name.lower())
    rows = []
    for pdf in pdfs:
        pages = read_pdf_pages(pdf)
        n_target = target_questions(len(pages)) if question_types else 0
        prompt = fill_prompt(prompt_template, args.language, question_types, notes_wanted, len(pages))
        key = hashlib.sha256(
            prompt.encode() + schema_text.encode() + pdf.read_bytes() + args.model.encode()
        ).hexdigest()
        print(f"... {pdf.name[:55]} ({len(pages)} pages, target {n_target})", flush=True)
        raw = generate(client, args.model, pdf, prompt, schema, key, args.rescore)

        row = {"pdf": pdf.name, "pages": len(pages), "target": n_target}
        if "error" in raw:
            row.update(score=0.0, error=raw["error"])
        else:
            try:
                deck = json.loads(raw["text"])
                row.update(score_deck(deck, pages, args.language, schema, question_types, notes_wanted))
            except (json.JSONDecodeError, TypeError) as e:
                row.update(score=0.0, error=f"invalid JSON ({raw['finish_reason']}): {e}")
            cost = (raw["input_tokens"] * price_in + (raw["output_tokens"] + raw["thinking_tokens"]) * price_out) / 1e6
            row.update({k: raw[k] for k in ("input_tokens", "output_tokens", "thinking_tokens", "seconds", "finish_reason")},
                       cost_usd=round(cost, 4))
        rows.append(row)

    # ---- report
    print()
    print(f"Model {args.model} · explanations in {args.language} · types {question_types or 'none'}"
          f" · notes {'on' if notes_wanted else 'off'}")
    cols = ["validity", "grounding", "mix", "uniqueness", "language", "notes"]
    print(f"{'PDF':38} {'score':>5} {'valid':>5} {'grnd':>5} {'mix':>5} {'uniq':>5} {'lang':>5} {'notes':>5}"
          f" {'n/tgt':>6} {'out+think':>9} {'$':>7}")
    for r in rows:
        if "error" in r:
            print(f"{r['pdf'][:38]:38} ERROR {r['error'][:90]}")
            continue
        parts = " ".join(f"{r[c]:5.1f}" if c in r else f"{'-':>5}" for c in cols)
        print(f"{r['pdf'][:38]:38} {r['score']:5.1f} {parts} {r['questions']:>3}/{r['target']:<2} "
              f"{r['output_tokens'] + r['thinking_tokens']:>9} {r['cost_usd']:7.4f}")
    scores = [r["score"] for r in rows]
    costs = [r["cost_usd"] for r in rows if "cost_usd" in r]
    if rows:
        print(f"\nAVERAGE SCORE {sum(scores) / len(scores):.1f}%  ·  avg cost/deck ${sum(costs) / max(len(costs), 1):.4f}"
              f"  ·  total ${sum(costs):.4f}  ·  {len(rows)} PDFs")

    RESULTS_DIR.mkdir(exist_ok=True)
    out = RESULTS_DIR / f"{datetime.now():%Y%m%d-%H%M%S}_{args.model}_{args.language}.json"
    out.write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"Details: {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
