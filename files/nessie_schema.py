"""Run:  python nessie_schema.py

Asks Nessie itself which fields its money-moving requests need, so we can match them exactly.
Safe to paste the output here (it never prints your key).
"""
import requests

import nessie

WANTED = ("transfer", "deposit", "withdraw", "purchase")
SPEC_PATHS = ("/openapi.json", "/api/openapi.json", "/swagger.json", "/v1/openapi.json")


def show_schema(name, schema):
    print(f"\n{name}")
    print("  required:", schema.get("required", []))
    for field, info in (schema.get("properties") or {}).items():
        bits = [info.get("type") or info.get("$ref", "").split("/")[-1] or "any"]
        if "enum" in info:
            bits.append("one of " + ", ".join(map(str, info["enum"])))
        if "anyOf" in info:
            bits.append("or ".join(str(o.get("type", o.get("$ref", ""))) for o in info["anyOf"]))
        print(f"  - {field}: {' | '.join(b for b in bits if b)}")


def main():
    if not nessie.enabled():
        print("No NESSIE_API_KEY found in .env")
        return
    for base in nessie._bases():
        for path in SPEC_PATHS:
            try:
                r = requests.get(base + path, params={"key": nessie.api_key()}, timeout=8)
            except requests.RequestException as e:
                print(f"{base}{path} -> unreachable ({e.__class__.__name__})")
                break
            ctype = r.headers.get("content-type", "")
            print(f"{base}{path} -> {r.status_code}")
            if r.ok and "json" in ctype:
                spec = r.json()
                print("\nEndpoints that move money:")
                for p, methods in spec.get("paths", {}).items():
                    if any(w in p.lower() for w in WANTED):
                        print(f"  {', '.join(m.upper() for m in methods)}  {p}")
                for name, schema in (spec.get("components", {}).get("schemas", {})).items():
                    if any(w in name.lower() for w in WANTED) and "create" in name.lower():
                        show_schema(name, schema)
                return
    print("\nCouldn't find a machine-readable spec.")
    print("Open Nessie's interactive docs, expand POST /accounts/{id}/transfers,")
    print("and screenshot the request-body fields instead.")


if __name__ == "__main__":
    main()
