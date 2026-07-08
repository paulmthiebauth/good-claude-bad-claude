# Worked example

One end-to-end run, to calibrate the *why* tone (Step 2) and the apply-now rule
(Step 6). Illustrative — do not copy the content, match the shape.

Context inferred: repo `checkout-api`, stack Python, context "pytest fixtures".

## Assembled `good` field

```
CODE:
@pytest.fixture
def order(db):
    return OrderFactory(status="paid")

WHY:
A factory fixture gives every test a valid order in one line, so tests state
only what they change from the baseline.
```

## Assembled `bad` field

```
CODE:
def test_refund(db):
    order = Order(id=1, status="paid", total=10, currency="usd", ...)
    db.add(order); db.commit()

WHY:
Hand-building the model inline repeats setup in every test and breaks them all
when a required column is added.
```

## Synthesized apply-now rule (Step 6)

> When writing pytest tests, prefer a factory fixture for domain objects; avoid
> hand-constructing models inline. Why: one-line valid baseline, resilient to
> schema changes.
