#!/usr/bin/env python3
"""Run an abstract-screening experiment.

Reads an experiment YAML and, for each (condition x abstract x run_index),
calls Claude with the codebook prompt and writes one structured JSON record
per call to runs/{experiment_id}/{condition}/.

Structured output is enforced by passing the prompt's schema sidecar as a
tool input_schema with tool_choice forcing the model to call that tool;
the response is then validated again with jsonschema as a belt-and-braces
check.

Usage
-----
    .venv/bin/python code/03_run_screening.py experiments/exp_001_codebook.yaml
    .venv/bin/python code/03_run_screening.py experiments/exp_001_codebook.yaml --limit 2
"""

from __future__ import annotations

import argparse
import hashlib
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import anthropic
import jsonschema
import pandas as pd
import yaml
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")


def sha8(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:8]


def utc_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def call_claude(client, model, temperature, max_tokens, prompt, schema):
    """Single Claude call. Uses tool_use to force schema-conforming output."""
    tool = {
        "name": "submit_decision",
        "description": "Submit the structured screening decision for one abstract.",
        "input_schema": schema,
    }
    resp = client.messages.create(
        model=model,
        max_tokens=max_tokens,
        temperature=temperature,
        tools=[tool],
        tool_choice={"type": "tool", "name": "submit_decision"},
        messages=[{"role": "user", "content": prompt}],
    )
    tool_block = next(b for b in resp.content if b.type == "tool_use")
    return tool_block.input, resp.usage, resp.stop_reason


def main(config_path: Path, limit: int | None) -> None:
    config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    exp_id = config["id"]
    model = config["model"]
    temperature = float(config.get("temperature", 0.0))
    max_tokens = int(config.get("max_tokens", 1024))
    n_runs = int(config.get("n_runs", 1))
    seed = config.get("seed")

    corpus = pd.read_csv(ROOT / config["inputs"]["manifest"])
    if limit:
        corpus = corpus.head(limit)

    client = anthropic.Anthropic()
    runs_root = ROOT / "runs" / exp_id

    total_in = total_out = 0
    t_start = time.monotonic()

    for cond in config["conditions"]:
        cond_name = cond["name"]
        prompt_path = ROOT / cond["prompt"]
        prompt_text = prompt_path.read_text(encoding="utf-8")
        prompt_id = prompt_path.stem
        prompt_sha = sha8(prompt_text)

        # Schema sidecar lives next to the prompt: <stem>.schema.json
        schema_path = prompt_path.with_suffix(".schema.json")
        schema = json.loads(schema_path.read_text(encoding="utf-8"))

        out_dir = runs_root / cond_name
        out_dir.mkdir(parents=True, exist_ok=True)

        print(
            f"[{exp_id}/{cond_name}] model={model} cases={len(corpus)} runs={n_runs}",
            flush=True,
        )

        for _, row in corpus.iterrows():
            case_id = row["case_id"]
            abstract_block = f"Title: {row['title']}\n\n{row['abstract']}"
            filled_prompt = prompt_text.replace("{{ABSTRACT}}", abstract_block)

            for run_index in range(1, n_runs + 1):
                t0 = time.monotonic()
                output, usage, stop_reason = call_claude(
                    client, model, temperature, max_tokens, filled_prompt, schema
                )
                jsonschema.validate(output, schema)

                ts = utc_iso()
                record = {
                    "experiment_id": exp_id,
                    "condition": cond_name,
                    "prompt_id": prompt_id,
                    "prompt_sha": prompt_sha,
                    "case_id": case_id,
                    "run_index": run_index,
                    "model": model,
                    "temperature": temperature,
                    "seed": seed,
                    "timestamp": ts,
                    "title": row["title"],
                    "abstract": row["abstract"],
                    "output": output,
                    "usage": {
                        "input_tokens": usage.input_tokens,
                        "output_tokens": usage.output_tokens,
                    },
                    "stop_reason": stop_reason,
                    "elapsed_sec": round(time.monotonic() - t0, 2),
                }
                ts_safe = ts.replace(":", "").replace("-", "")
                out_path = out_dir / f"{case_id}__{run_index:03d}__{ts_safe}.json"
                out_path.write_text(json.dumps(record, indent=2), encoding="utf-8")

                total_in += usage.input_tokens
                total_out += usage.output_tokens
                print(
                    f"  {case_id} run {run_index} -> {output['consort_flag']:<12} "
                    f"({usage.input_tokens}+{usage.output_tokens} tok, "
                    f"{record['elapsed_sec']}s)",
                    flush=True,
                )

    elapsed = time.monotonic() - t_start
    print(
        f"\ndone. {total_in} input + {total_out} output tokens in {elapsed:.1f}s",
        flush=True,
    )


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("config", help="path to experiment YAML")
    ap.add_argument(
        "--limit",
        type=int,
        default=None,
        help="limit corpus to first N abstracts (smoke test)",
    )
    args = ap.parse_args()
    main(Path(args.config), args.limit)
