from __future__ import annotations

import argparse
from pathlib import Path

from pydantic import ValidationError

from structured_parser import parse_text_file, save_failed_output, save_promotions_json


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Parse one local text file into structured promotion JSON."
    )

    parser.add_argument(
        "--input",
        required=True,
        help="Path to local raw text file, e.g. raw_text/chipotle.txt",
    )
    parser.add_argument(
        "--brand",
        required=True,
        help="Brand/business name, e.g. Chipotle",
    )
    parser.add_argument(
        "--category",
        default=None,
        help="Optional category, e.g. food, coffee, retail",
    )
    parser.add_argument(
        "--model",
        choices=["rule_based", "ollama"],
        default="rule_based",
        help="Extraction backend. Default: rule_based",
    )
    parser.add_argument(
        "--ollama-model",
        default="llama3.1:8b",
        help="Ollama model name (only used when --model ollama). Default: llama3.1:8b",
    )
    parser.add_argument(
        "--ollama-host",
        default="http://localhost:11434",
        help="Ollama host URL. Default: http://localhost:11434",
    )
    parser.add_argument(
        "--ollama-timeout",
        type=int,
        default=600,
        help="Seconds before an Ollama request times out. Default: 600",
    )

    args = parser.parse_args()

    input_path = Path(args.input)

    if not input_path.exists():
        raise FileNotFoundError(f"Input file does not exist: {input_path}")

    try:
        promotions = parse_text_file(
            input_path=input_path,
            brand=args.brand,
            category=args.category,
            model_type=args.model,
            ollama_model=args.ollama_model,
            ollama_host=args.ollama_host,
            ollama_timeout=args.ollama_timeout,
        )
        output_path = save_promotions_json(
            promotions=promotions,
            brand=args.brand,
            input_path=input_path,
        )
        print(f"Saved {len(promotions)} promotion(s) to: {output_path}")

    except ValidationError as e:
        failed_path = save_failed_output(
            raw_data={"input_path": str(input_path)},
            brand=args.brand,
            input_path=input_path,
            error=e,
        )
        print(f"Validation failed. Saved failure details to: {failed_path}")
        raise

    except Exception as e:
        failed_path = save_failed_output(
            raw_data={"input_path": str(input_path)},
            brand=args.brand,
            input_path=input_path,
            error=e,
        )
        print(f"Parsing failed. Saved failure details to: {failed_path}")
        raise


if __name__ == "__main__":
    main()