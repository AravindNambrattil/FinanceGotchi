"""Short AI-written text for the app (decision results, spending insight, tips, goal advice).

The model runs on THIS server (Ollama + Qwen), so there is no third-party API and no key. It never decides anything:
the app sends finished facts, the model writes a sentence around them, and every answer is checked before it is used.

    POST /pets/{id}/ai/text   {"kind": "decision|insight|tips|goal", "facts": {...}}  -> {"text", "lines", ...}
    POST /pets/{id}/ai/chat   {"message", "facts": {...}, "history": [{role, text}]}  -> {"text", "reason", ...}
    GET  /pets/{id}/ai/status                                                        -> is the model reachable?

`text` is null whenever the model is slow, busy, down, or wrote something that failed the checks. The app then shows
its built-in text, so nothing on screen ever depends on the model.

Facts use a naming convention so the checker knows what each number means:
    *_usd   dollars   (amount_usd, goal_saved_usd)          *_pct    percentages (goal_pct)
    *_days, *_weeks, *_count   plain counts (streak_days)   anything else must be text
An answer may only contain $ amounts, % values and counts that appear in the facts, and each must be in the right
kind (a "$40" fact can never come back as "40%").

Settings (env vars, all optional): AI_MODEL (qwen2.5:3b), AI_URL (http://127.0.0.1:11434), AI_TIMEOUT (25),
AI_ENABLED (1). Read at call time so the server's .env applies.
"""
import json
import os
import re
import threading
import time
from collections import OrderedDict
from typing import Any, Dict, List, Optional

import requests
from fastapi import APIRouter
from pydantic import BaseModel, Field

router = APIRouter(prefix="/pets/{pet_id}/ai", tags=["ai"])

BASE_RULES = (
    "You write short text for a friendly personal-finance app that helps young people build healthy money habits. "
    "Speak to the user as \"you\". Use ONLY the numbers given in the facts, exactly as given; never calculate, "
    "estimate, round or invent numbers, and keep dollars as dollars and percentages as percentages. "
    "The fact \"summary\" states exactly what happened; stay true to it and never say something happened that it does not "
    "say (for example, do not say money was saved unless the summary says it was). Do not judge whether spending or "
    "savings are good or bad; only describe them. Be warm, calm and practical. Never shame or lecture about spending, "
    "never compare the user to other people, and never give investment, tax or legal advice. "
    "No emojis, no markdown, no hashtags."
)

# instruction, max words in the whole answer, max tokens to generate, few-shot examples (facts -> answer)
KINDS: Dict[str, dict] = {
    "decision": {
        "instruction": "Reply with ONE sentence of at most 22 words reacting to what just happened. Do not use the word \"but\". Do not give advice or say what to do next. Do not say anything about the emergency fund being full or well stocked.",
        "max_words": 30, "max_tokens": 60,
        "shots": [
            ({"event": "save", "summary": "Saved $25 for the Laptop goal instead of buying New headphones.", "amount_usd": 25,
              "goal": "Laptop", "goal_saved_usd": 745, "goal_target_usd": 1000, "goal_pct": 74, "goal_remaining_usd": 255},
             "Nice save! Skipping the headphones put $25 toward your Laptop, and you are now 74% of the way there."),
            ({"event": "buy", "summary": "Bought Concert tickets for $40, a want. Nothing was moved toward the Laptop goal.",
              "amount_usd": 40, "goal": "Laptop", "goal_pct": 72},
             "Enjoy the concert! Treats are part of a balanced life, and your Laptop goal is still 72% funded."),
            ({"event": "expense_not_covered", "summary": "An unexpected $90 Phone screen repair came up and the emergency fund could not fully cover it.",
              "amount_usd": 90, "emergency_fund_usd": 40},
             "The $90 phone screen repair was more than the $40 in your emergency fund."),
        ],
    },
    "insight": {
        "instruction": "Reply with 1 or 2 friendly sentences, at most 35 words in total, that only describe the recent activity. Never say whether spending or saving was good or bad, and give no advice.",
        "max_words": 45, "max_tokens": 90,
        "shots": [
            ({"summary": "Recent activity: saved $20 and spent $68 across 4 transactions; groceries was the biggest category.",
              "spent_usd": 68, "saved_usd": 20, "top_category": "groceries", "top_category_usd": 42, "transactions_count": 4},
             "You saved $20 and spent $68 recently, with groceries the biggest part at $42."),
        ],
    },
    "tips": {
        "instruction": "Reply with exactly 3 short tips, one per line, each at most 16 words. No numbering, no bullets.",
        "max_words": 60, "max_tokens": 110,
        "shots": [
            ({"summary": "Laptop goal is 72% funded, a 4-day saving streak, emergency fund is still being built (22%).",
              "goal": "Laptop", "goal_pct": 72, "streak_days": 4, "emergency_pct": 22, "emergency_status": "still being built"},
             "Keep your 4-day saving streak going with a small save today.\n"
             "Your Laptop is 72% funded, so the finish line is getting close.\n"
             "A bigger emergency fund means surprises will not derail your goals."),
        ],
    },
    "goal": {
        "instruction": "Reply with ONE sentence of at most 25 words giving a practical, encouraging suggestion for this goal.",
        "max_words": 32, "max_tokens": 70,
        "shots": [
            ({"summary": "Laptop goal is 72% funded with $280 to go; about $22 a week finishes it in 13 weeks.",
              "goal": "Laptop", "goal_pct": 72, "goal_remaining_usd": 280, "weekly_needed_usd": 22, "left_weeks": 13},
             "Setting aside about $22 a week gets your Laptop funded in 13 weeks."),
        ],
    },
}

# Chat: Mochi as a friendly coach for money habits AND everyday wellbeing (movement, sleep, routines, stress).
# The system prompt is kept short and stable so Ollama can reuse its cached prefix: this CPU reads only ~40 prompt
# tokens/s, so every extra token in the prompt costs time. Shots are plain (question, answer) pairs with no numbers.
CHAT_SYSTEM = (
    "You are Mochi, a warm, upbeat pet companion in a wellbeing app that helps young people build healthy habits with "
    "money, movement and everyday life. Chat like a supportive friend, in 1 to 3 short sentences (under 55 words). "
    "You can talk about saving and everyday money habits, being active, sleep, stress, routines, study and work balance, "
    "and small goals. When asked for advice, give one or two gentle, practical ideas, tied to the person's own facts when "
    "that helps. Never shame or judge anyone, and never say spending is good or bad. "
    "You are not a doctor, therapist or financial adviser: no diagnoses, medicine, diets or weight targets, and no "
    "investing, tax or legal advice; for anything serious, suggest talking to a professional or someone they trust. "
    "Use a number only if it appears in the facts below, exactly as given; never invent numbers about the person and "
    "keep general tips free of numbers: never name a dollar amount, percentage or length of time that is not in the facts "
    "(say a small amount each week, a short walk, a regular bedtime). Do not say anything about the "
    "person that the facts do not say. If asked about something unrelated (like coding or homework), kindly say that is "
    "outside what you can help with and steer back to their habits and goals. No emojis, no markdown."
)
KINDS["chat"] = {
    "instruction": "",
    "max_words": 60, "max_tokens": 120,
    "shots": [
        ("I feel like I never save anything, any tips?",
         "Small and steady wins here. Pick a tiny amount you barely notice and save it on the same day each week, "
         "so it becomes a habit rather than a decision."),
        ("I have been sitting all day and feel sluggish",
         "That happens! A short walk or some stretching can wake you up, and it gives me a little energy boost too."),
        ("Write me a python script",
         "That one is outside what I can help with, but I would love to chat about your goals, your energy or how your "
         "week is going!"),
    ],
}

CHAT_SHORTCUTS = [
    # (pattern on the question, fixed reply, reason). Never sent to the model.
    (re.compile(r"\b(suicid\w*|kill myself|killing myself|end my life|want to die|self[- ]?harm\w*|hurt myself|"
                r"hurting myself|cut myself|no reason to live)\b", re.I),
     "I'm really sorry you're going through this. You deserve support from a real person right now. If you are in the US, "
     "you can call or text 988 any time, or contact your local emergency number. Please reach out to someone you trust too.",
     "crisis"),
    (re.compile(r"\b(stocks?|shares?|invest\w*|crypto\w*|bitcoin|etf|401k|ira|mutual funds?|tax(?:es)?|"
                r"loans?|mortgage|lawsuit|legal|lawyer|insurance|gambl\w*|bet(?:s|ting)?)\b", re.I),
     "I can't give investment, tax or legal advice, but I'm happy to talk about your goals, your emergency fund and "
     "your saving habits.",
     "off limits"),
    (re.compile(r"\b(diagnos\w*|medication|medicine|prescri\w*|dosage|symptoms?|anorexi\w*|bulimi\w*|"
                r"eating disorder|pregnan\w*|lose weight|weight loss|diet)\b", re.I),
     "I'm not a doctor, so that one is best asked to a doctor or pharmacist. I'm happy to chat about staying active, "
     "sleep routines or your goals though!",
     "medical"),
]
# Words Mochi must never use in an answer (advice we don't give). Judging spending is banned everywhere.
CHAT_ANSWER_BANNED = re.compile(r"\b(invest\w*|stocks?|crypto\w*|bitcoin|etf|mortgage|diagnos\w*|prescri\w*|"
                                r"medication|dosage|calorie|diet|good spending|bad spending|wasteful|irresponsible|"
                                r"reckless|careless|guilt\w*|splurg\w*|overspend\w*|lazy|fully funded)\b", re.I)
# Send the model only the facts a question is about. Mixing money and health facts made the 3B model cross them
# ("save more" -> "use your 140 active kcal"), and every extra fact is prompt the CPU has to read.
HEALTH_KEYS = {"steps_count", "active_energy_kcal_count", "exercise_minutes_count", "energy_pct"}
BASIC_KEYS = {"pet", "mood", "streak_days", "goal", "goal_pct"}
HEALTH_TOPIC = re.compile(r"\b(active|activity|steps?|walk\w*|run\w*|exercis\w*|workout\w*|energy|energetic|sleep\w*|tired|"
                          r"stress\w*|anxi\w*|health\w*|mov(?:e|ing)|stretch\w*|calm|relax\w*|routine|focus\w*|exams?|"
                          r"study\w*|mood|sluggish|rest|body|fit\w*)\b", re.I)
MONEY_TOPIC = re.compile(r"\b(sav\w*|goals?|money|emergency|funds?|spen[dt]\w*|balance|budget\w*|streak|laptop|cash|afford|"
                         r"buy\w*|bought|expens\w*|income|paycheck|dollars?|bank\w*|purchase\w*)\b|\$", re.I)


def facts_for_question(question: str, facts: Dict[str, Any]) -> Dict[str, Any]:
    health, money = bool(HEALTH_TOPIC.search(question)), bool(MONEY_TOPIC.search(question))
    if health and money:
        return facts
    if health:
        keep = BASIC_KEYS - {"goal", "goal_pct"} | HEALTH_KEYS
    elif money:
        keep = set(facts) - HEALTH_KEYS
    else:
        keep = BASIC_KEYS
    return {k: v for k, v in facts.items() if k in keep and not (k == "summary" and health and not money)}


# Numbers inside a *suggestion* ("try setting aside $10 a week", "a 10 minute walk") are not claims about the person, so
# small round ones are allowed there. Everything else in a chat answer is still checked against the facts: a sentence
# that states something about the person, a percentage, or any other amount is never let through.
SUGGESTION = re.compile(r"\b(try|could|might|maybe|aim|how about|why not|consider|start with|even|set aside|put aside|"
                        r"a good|can help|helps)\b", re.I)
TIP_DOLLARS = re.compile(r"\$\s?(?:5|10|15|20|25|30|40|50)(?![\d.,]\d)")
TIP_MINUTES = re.compile(r"\b(?:5|10|15|20|30)[- ]?(?:minutes?|mins?)\b", re.I)
TIP_HOURS = re.compile(r"\b(?:[5-9]|1[0-2])(?:\s?(?:-|to)\s?(?:[5-9]|1[0-2]))?[- ]?hours?\b", re.I)


def without_suggestion_numbers(text: str) -> str:
    out = []
    for sentence in re.split(r"(?<=[.!?])\s+", text):
        if SUGGESTION.search(sentence):
            for pattern in (TIP_DOLLARS, TIP_MINUTES, TIP_HOURS):
                sentence = pattern.sub("some", sentence)
        out.append(sentence)
    return " ".join(out)


EMOJI = re.compile("[\U0001F300-\U0001FAFF\u2600-\u27BF]")
CHAT_HISTORY_TURNS = 6

MAX_ATTEMPTS = 3
CHAT_ATTEMPTS = 2  # a typed question is waited on, so a failure should come back fast
CACHE_TTL_SECONDS = 600
CACHE_MAX = 256
_cache: "OrderedDict[str, tuple]" = OrderedDict()
_cache_lock = threading.Lock()
_model_lock = threading.Lock()  # the model answers one request at a time


# ---------------------------------------------------------------- settings
def enabled() -> bool:
    return os.environ.get("AI_ENABLED", "1") not in ("0", "false", "off", "")


def base_url() -> str:
    return os.environ.get("AI_URL", "http://127.0.0.1:11434").rstrip("/")


def model_name() -> str:
    return os.environ.get("AI_MODEL", "qwen2.5:3b")


def threads() -> int:
    try:
        return max(1, int(os.environ.get("AI_THREADS", "4")))
    except ValueError:
        return 4


def timeout() -> float:
    try:
        return float(os.environ.get("AI_TIMEOUT", "25"))
    except ValueError:
        return 25.0


# ---------------------------------------------------------------- facts
KEY_RE = re.compile(r"^[a-z][a-z0-9_]{0,31}$")


def clean_facts(raw: Dict[str, Any]) -> Dict[str, Any]:
    """Only well-named keys with short text or plain numbers get through, so nothing odd reaches the prompt."""
    facts: Dict[str, Any] = {}
    for key, value in list(raw.items())[:32]:
        if not KEY_RE.match(str(key)):
            continue
        if isinstance(value, bool):
            continue
        if isinstance(value, (int, float)):
            facts[key] = int(value) if float(value).is_integer() else round(float(value), 2)
        elif isinstance(value, str):
            text = re.sub(r"[\x00-\x1f\x7f]+", " ", value).strip()[: 160 if key == "summary" else 60]
            if text:
                facts[key] = text
    return facts


def _numbers(facts: Dict[str, Any], suffixes) -> set:
    return {float(v) for k, v in facts.items()
            if isinstance(v, (int, float)) and any(k.endswith(s) for s in suffixes)}


def _same(value: float, allowed: set) -> bool:
    return any(abs(value - a) < 0.005 for a in allowed)


# ---------------------------------------------------------------- checking the answer
DOLLAR_RE = re.compile(r"\$\s?(\d[\d,]*(?:\.\d+)?)")
PERCENT_RE = re.compile(r"(\d+(?:\.\d+)?)\s?%")
BARE_RE = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])")


def answer_problem(text: str, facts: Dict[str, Any], max_words: int) -> Optional[str]:
    """Why an answer must be thrown away, or None if it is fine."""
    if not text.strip():
        return "empty"
    if len(text.split()) > max_words:
        return "too long"
    if re.search(r"[*#`_]{2,}|https?://|\n\s*[-*•]\s", text):
        return "markdown or link"
    dollars = _numbers(facts, ("_usd",))
    percents = _numbers(facts, ("_pct",))
    counts = _numbers(facts, ("_days", "_weeks", "_count"))

    rest = text
    for match in DOLLAR_RE.findall(text):
        if not _same(float(match.replace(",", "")), dollars):
            return f"dollar amount ${match} is not in the facts"
    rest = DOLLAR_RE.sub(" ", rest)
    for match in PERCENT_RE.findall(rest):
        if not _same(float(match), percents):
            return f"percentage {match}% is not in the facts"
    rest = PERCENT_RE.sub(" ", rest)
    for match in BARE_RE.findall(rest):
        if not _same(float(match), counts):
            return f"number {match} is not in the facts"
    return None


# Phrases that judge spending or sound like a lecture: never allowed, whatever the event.
BANNED_PHRASES = ("good spending", "bad spending", "poor spending", "overspend", "wasteful", "waste ", "irresponsible",
                  "careless", "you should not", "you shouldn't", "too much", "guilt", "splurg", "reckless",
                  # lectures and soft guilt-trips
                  "let's focus", "let us focus", "focus on saving", "is important", "you must", "you need to",
                  "make sure", "remember to", "next time", "consider boosting", "consider saving", "'s important",
                  "important to", "priority", "fully funded", "well-stocked", "well stocked", "fully stocked",
                  "smart choice", "smart way", "wise choice", "good choice", "good decision", "bad choice")

# Words that would make an answer false for a given event (the number check can't see these mistakes).
EVENT_FORBIDDEN = {
    # " but " is banned after a purchase: "treat, BUT your goal..." reads as a guilt trip. Spending is never punished.
    "buy": ("saved", "saving", "put toward", "toward your", "towards your", "covers some", "added to your", " but "),
    "later": ("saved", "saving", "bought", "purchased", "spent", "enjoy your new"),
    "save": ("bought", "purchased", "you spent"),
    "expense_covered": ("not covered", "couldn't cover", "could not cover", "wasn't covered", "didn't cover"),
    "expense_not_covered": ("covered it", "handled it", "was covered", "fully covered", "paid for it"),
}


PRAISE = re.compile(r"\b(great|good|nice|smart|wise|well done|awesome|excellent|proud|fantastic|amazing|kudos|bravo)\b", re.I)
ADVICE = re.compile(r"\b(consider|focus|keep (?:in mind|tracking|track|up|going)|stay|try to|should|need to|must|make sure|"
                    r"remember|let's|let us|budget|save more)\b", re.I)
STRICT_ADVICE = re.compile(r"\b(should|must|need to|make sure|remember|let's|let us|budget)\b", re.I)
CLOSE = re.compile(r"\b(almost there|nearly there|so close|almost done|nearly done|just about there|in no time|before you know it)\b", re.I)


SAVE_WORD = re.compile(r"\bsav(?:e|es|ed|ing|ings)\b", re.I)


def meaning_problem(text: str, facts: Dict[str, Any], kind: str = "decision") -> Optional[str]:
    """Things a number check can't see: false meaning, judging, advice, and praise where it isn't earned.

    Praise is only for a save. A purchase, a deferral or an unexpected expense gets neutral wording, so spending is
    never judged either way. Results and insights describe; only goal advice may suggest something.
    """
    lower = text.lower()
    event = str(facts.get("event", ""))
    if EMOJI.search(text):
        return "emoji"
    if kind == "chat":
        found = CHAT_ANSWER_BANNED.search(text)
        if found:
            return f"'{found.group(0)}' is not something Mochi says"
        pct = facts.get("goal_pct")
        if isinstance(pct, (int, float)) and pct < 75 and CLOSE.search(text):
            return f"says the goal is close but it is only {pct}% funded"
        return None
    for phrase in BANNED_PHRASES:
        if phrase in lower:
            return f"judgemental phrase '{phrase.strip()}'"
    for phrase in EVENT_FORBIDDEN.get(event, ()):
        if phrase in lower:
            return f"'{phrase}' contradicts the event '{event}'"
    if kind == "decision" and event in ("buy", "later") and SAVE_WORD.search(text):
        return f"mentions saving after a '{event}' decision, when nothing was saved"
    if kind == "insight" or (kind == "decision" and event != "save"):
        found = PRAISE.search(text)
        if found:
            return f"praise word '{found.group(0)}' where it isn't earned"
    if kind in ("decision", "insight"):
        found = ADVICE.search(text)
        if found:
            return f"advice '{found.group(0)}' where only a description is wanted"
    elif kind == "goal":
        found = STRICT_ADVICE.search(text)
        if found:
            return f"pushy word '{found.group(0)}'"
    pct = facts.get("goal_pct")
    if isinstance(pct, (int, float)) and pct < 75 and CLOSE.search(text):
        return f"says the goal is close but it is only {pct}% funded"
    return None


def tidy(text: str) -> str:
    text = text.strip().strip("\"'“”")
    text = re.sub(r"[ \t]+", " ", text)
    return text


def parse(kind: str, text: str):
    """(joined text, lines). Tips are several lines; everything else is one paragraph."""
    text = tidy(text)
    if kind == "tips":
        lines = [re.sub(r"^\s*(?:[-*•]|\d+[.)])\s*", "", ln).strip() for ln in text.splitlines()]
        lines = [ln for ln in lines if ln]
        return "\n".join(lines[:3]), lines[:3]
    flat = " ".join(text.split())
    return flat, [flat] if flat else []


# ---------------------------------------------------------------- talking to the model
class ModelUnavailable(Exception):
    pass


def chat(messages: List[dict], max_tokens: int, seconds: float, temperature: float = 0.4) -> str:
    body = {"model": model_name(), "stream": False, "keep_alive": "24h", "messages": messages,
            "options": {"temperature": temperature, "num_predict": max_tokens, "num_thread": threads()}}
    try:
        r = requests.post(f"{base_url()}/api/chat", json=body, timeout=seconds)
        r.raise_for_status()
        return r.json()["message"]["content"]
    except (requests.RequestException, KeyError, ValueError) as e:
        raise ModelUnavailable(str(e)) from e


def clean_text(value: Any, limit: int) -> str:
    return re.sub(r"[\x00-\x1f\x7f]+", " ", str(value)).strip()[:limit]


def clean_history(raw: Any) -> List[dict]:
    """The last few turns of a chat, as plain user/assistant messages. Anything odd is dropped."""
    turns = []
    for item in (raw if isinstance(raw, list) else [])[-CHAT_HISTORY_TURNS:]:
        if not isinstance(item, dict) or item.get("role") not in ("user", "assistant"):
            continue
        text = clean_text(item.get("text", ""), 300)
        if text:
            turns.append({"role": item["role"], "text": text})
    return turns


def build_messages(kind: str, facts: Dict[str, Any], question: Optional[str] = None,
                   history: Optional[List[dict]] = None) -> List[dict]:
    spec = KINDS[kind]
    messages = [{"role": "system", "content": f"{BASE_RULES} {spec['instruction']}"}]
    if kind == "chat":
        # Facts go in the system message (sorted, compact) so the whole prefix stays identical between turns and Ollama
        # reuses its cache instead of re-reading it at ~40 tokens/s.
        facts_line = json.dumps(facts, sort_keys=True, separators=(",", ":"))
        messages = [{"role": "system", "content": f"{CHAT_SYSTEM}\nFacts about the person: {facts_line}"}]
        for shot_question, answer in spec["shots"]:
            messages += [{"role": "user", "content": shot_question}, {"role": "assistant", "content": answer}]
        for turn in history or []:
            messages.append({"role": turn["role"], "content": turn["text"]})
        messages.append({"role": "user", "content": question or ""})
        return messages
    for shot_facts, answer in spec["shots"]:
        messages += [{"role": "user", "content": json.dumps(shot_facts)}, {"role": "assistant", "content": answer}]
    messages.append({"role": "user", "content": json.dumps(facts)})
    return messages


def generate(kind: str, raw_facts: Dict[str, Any], _chat=None, question: Optional[str] = None,
             history: Optional[List[dict]] = None) -> dict:
    """Never raises. `text` is None when the model is off, busy, slow, or its answer failed the checks."""
    started = time.monotonic()
    result = {"text": None, "lines": [], "model": model_name(), "cached": False, "reason": None, "ms": 0}

    def finish(reason=None):
        result["reason"] = reason
        result["ms"] = int((time.monotonic() - started) * 1000)
        return result

    if not enabled():
        return finish("disabled")
    if kind not in KINDS:
        return finish("unknown kind")
    facts = clean_facts(raw_facts)
    if not facts:
        return finish("no facts")

    if kind == "chat":
        question = clean_text(question or "", 300)
        if not question:
            return finish("no question")
        for pattern, reply, reason in CHAT_SHORTCUTS:
            if pattern.search(question):
                result.update(text=reply, lines=[reply])
                return finish(reason)
        history = clean_history(history)
        facts = facts_for_question(question, facts) or facts

    key = kind + "|" + json.dumps(facts, sort_keys=True) + (
        "|" + json.dumps([question, history]) if kind == "chat" else "")
    with _cache_lock:
        hit = _cache.get(key)
        if hit and time.time() - hit[0] < CACHE_TTL_SECONDS:
            _cache.move_to_end(key)
            result.update(text=hit[1], lines=hit[2], cached=True)
            return finish()

    spec = KINDS[kind]
    budget = timeout()
    # One request at a time. If someone else is mid-answer, don't queue up behind them.
    if not _model_lock.acquire(timeout=2.0):
        return finish("busy")
    try:
        problem = "no attempt"
        messages = build_messages(kind, facts, question, history)
        for attempt in range(CHAT_ATTEMPTS if kind == "chat" else MAX_ATTEMPTS):
            remaining = budget - (time.monotonic() - started)
            if remaining < 2.0:
                problem = "timed out"
                break
            try:
                # A little more variety on retries, so it doesn't repeat the same mistake.
                raw = (_chat or chat)(messages, spec["max_tokens"], remaining, temperature=0.4 if attempt == 0 else 0.6)
            except ModelUnavailable as e:
                return finish(f"model unavailable: {e}"[:120])
            text, lines = parse(kind, raw)
            if kind == "tips":
                # Judge each tip on its own, so one bad line doesn't throw away the good ones.
                lines = [ln for ln in lines
                         if answer_problem(ln, facts, 24) is None and meaning_problem(ln, facts, kind) is None]
                text = "\n".join(lines)
                problem = "no valid tips" if not lines else None
            else:
                problem = (answer_problem(without_suggestion_numbers(text) if kind == "chat" else text, facts,
                                          spec["max_words"]) or meaning_problem(text, facts, kind))
            if problem is None:
                with _cache_lock:
                    _cache[key] = (time.time(), text, lines)
                    while len(_cache) > CACHE_MAX:
                        _cache.popitem(last=False)
                result.update(text=text, lines=lines)
                return finish()
            # Tell the model exactly what was wrong and let it fix it: much better than a blind retry.
            messages = messages + [
                {"role": "assistant", "content": raw},
                {"role": "user", "content": f"That answer was not allowed ({problem}). Write a new answer that follows "
                                            "every rule, using only the facts."},
            ]
        return finish(f"rejected: {problem}")
    finally:
        _model_lock.release()


# ---------------------------------------------------------------- warm-up
def warm_up(delay: float = 8.0) -> None:
    """Load the model into memory shortly after the server starts, so the first real request is fast."""
    time.sleep(delay)
    if not enabled():
        return
    sample = {"pet": "Mochi", "mood": "happy", "streak_days": 3}
    try:
        # The chat prompt is the longest and most used, so it is the one worth having ready in the cache.
        chat(build_messages("chat", sample, "hi", []), 10, 90.0)
    except ModelUnavailable:
        pass


threading.Thread(target=warm_up, daemon=True).start()


# ---------------------------------------------------------------- endpoints
class TextIn(BaseModel):
    kind: str = Field(..., max_length=16)
    facts: Dict[str, Any] = Field(default_factory=dict)


@router.post("/text")
def write_text(pet_id: str, body: TextIn):
    return generate(body.kind, body.facts)


class ChatTurn(BaseModel):
    role: str = Field(..., max_length=12)
    text: str = Field(..., max_length=300)


class ChatIn(BaseModel):
    message: str = Field(..., max_length=300)
    facts: Dict[str, Any] = Field(default_factory=dict)
    history: List[ChatTurn] = Field(default_factory=list, max_length=CHAT_HISTORY_TURNS)


@router.post("/chat")
def chat_reply(pet_id: str, body: ChatIn):
    return generate("chat", body.facts, question=body.message, history=[t.model_dump() for t in body.history])


@router.get("/status")
def read_status(pet_id: str):
    info = {"enabled": enabled(), "model": model_name(), "available": False}
    if not info["enabled"]:
        return info
    try:
        tags = requests.get(f"{base_url()}/api/tags", timeout=3).json()
        info["available"] = any(m.get("name", "").startswith(model_name().split(":")[0]) and
                                m.get("name") == model_name() for m in tags.get("models", []))
    except (requests.RequestException, ValueError):
        pass
    return info
