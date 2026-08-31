#!/usr/bin/env python3
"""Tests for the pure parts of imgbench: parsing, scoring, ranking, the log.

Nothing here touches the network. The benchmark itself costs money to run, so
the logic that decides what a run *means* has to be verifiable without one.

    python3 -m unittest tools.imgbench.test_imgbench
"""

import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import store
from catalog import Observation, discount_from_endpoints, parse_models, rank
from fidelity import missing, normalize, score_transcription


class ParsingTests(unittest.TestCase):
    def test_keeps_only_image_capable_models(self):
        payload = {
            "data": [
                {
                    "id": "vendor/draws",
                    "architecture": {"output_modalities": ["image", "text"]},
                    "pricing": {"image": "0.05"},
                },
                {
                    "id": "vendor/text-only",
                    "architecture": {"output_modalities": ["text"]},
                    "pricing": {"prompt": "0.000001"},
                },
            ]
        }
        models = parse_models(payload)
        self.assertEqual([m.id for m in models], ["vendor/draws"])

    def test_excludes_routing_aliases(self):
        # `openrouter/auto` is a dispatcher; benchmarking it measures whatever
        # it happened to pick, which is not a fact about any model.
        payload = {
            "data": [
                {
                    "id": "openrouter/auto",
                    "architecture": {"output_modalities": ["image"]},
                    "pricing": {"prompt": "-1"},
                },
                {
                    "id": "vendor/real",
                    "architecture": {"output_modalities": ["image"]},
                    "pricing": {"image": "0.05"},
                },
            ]
        }
        self.assertEqual([m.id for m in parse_models(payload)], ["vendor/real"])

    def test_unquoted_price_is_none_not_zero(self):
        # The catalog leaves `image` blank for most image models. Reading that
        # as free would rank an unknown price as the cheapest thing available.
        payload = {
            "data": [
                {
                    "id": "vendor/blank",
                    "architecture": {"output_modalities": ["image"]},
                    "pricing": {"image": ""},
                }
            ]
        }
        self.assertIsNone(parse_models(payload)[0].quoted_image)


class DiscountTests(unittest.TestCase):
    def test_reads_the_discount_of_the_quoted_endpoint(self):
        # Providers are promoted individually and the deepest discount is
        # usually not the endpoint you get. Reporting it would call a stable
        # price promotional, inverting the meaning of the column.
        payload = {
            "data": {
                "endpoints": [
                    {"pricing": {"image": "0.05", "discount": "0.0"}},
                    {"pricing": {"image": "0.09", "discount": "0.5"}},
                ]
            }
        }
        self.assertEqual(discount_from_endpoints(payload, 0.05), 0.0)

    def test_falls_back_to_cheapest_when_no_endpoint_matches(self):
        payload = {
            "data": {
                "endpoints": [
                    {"pricing": {"image": "0.09", "discount": "0.5"}},
                    {"pricing": {"image": "0.20", "discount": "0.1"}},
                ]
            }
        }
        self.assertEqual(discount_from_endpoints(payload, 0.99), 0.5)

    def test_nothing_served_is_zero(self):
        self.assertEqual(discount_from_endpoints({"data": {"endpoints": []}}, 0.05), 0.0)


class ScoringTests(unittest.TestCase):
    def test_all_targets_present_scores_one(self):
        self.assertEqual(
            score_transcription(("みなみぐち", "南口"), "みなみぐち\n南口"), 1.0
        )

    def test_a_nearly_right_render_scores_zero_for_that_target(self):
        # The failure this benchmark exists to catch: gemini-2.5-flash-image
        # drew みなみりぢち for みなみぐち. Sharing four characters must not earn
        # partial credit -- a wrong glyph teaches a wrong letterform.
        self.assertEqual(
            score_transcription(("みなみぐち",), "みなみりぢち"), 0.0
        )

    def test_partial_credit_is_per_target_not_per_character(self):
        score = score_transcription(("みなみぐち", "南口"), "みなみぐち only")
        self.assertEqual(score, 0.5)

    def test_extra_text_is_not_a_fault(self):
        # Real signs carry background text; the verifier transcribes it too.
        self.assertEqual(
            score_transcription(("でぐち",), "JR\nでぐち\nEXIT"), 1.0
        )

    def test_normalization_folds_width_and_space_only(self):
        self.assertEqual(normalize("アイス コーヒー"), normalize("アイスコーヒー"))
        self.assertEqual(normalize("１５０円"), normalize("150円"))
        # Dakuten and vowel length are the whole point and must survive.
        self.assertNotEqual(normalize("レギュラー"), normalize("レキュラー"))
        self.assertNotEqual(normalize("みなみぐち"), normalize("みなみくち"))

    def test_missing_names_what_went_wrong(self):
        self.assertEqual(
            missing(("アイスコーヒー", "レギュラーサイズ"), "アイスコーヒー"),
            ["レギュラーサイズ"],
        )


class RankingTests(unittest.TestCase):
    def test_fidelity_outranks_price(self):
        cheap_and_wrong = Observation(
            id="cheap", measured_image=0.039, fidelity=0.60, samples=4
        )
        dearer_and_right = Observation(
            id="good", measured_image=0.068, fidelity=1.0, samples=4
        )
        self.assertEqual(
            [o.id for o in rank([cheap_and_wrong, dearer_and_right])],
            ["good", "cheap"],
        )

    def test_rejected_models_are_kept_not_dropped(self):
        # A run should record why a model was rejected, not silently omit it.
        observations = [
            Observation(id="bad", measured_image=0.01, fidelity=0.5),
            Observation(id="ok", measured_image=0.07, fidelity=1.0),
        ]
        self.assertEqual(len(rank(observations)), 2)

    def test_cost_per_correct_image_accounts_for_waste(self):
        observation = Observation(id="x", measured_image=0.04, fidelity=0.5)
        effective = observation.cost_per_correct_image
        assert effective is not None
        self.assertAlmostEqual(effective, 0.08)

    def test_unmeasured_model_is_not_usable(self):
        self.assertFalse(Observation(id="x").usable)

    def test_threshold_rejects_nine_in_ten(self):
        # 90% still means a wrong glyph in most sentences, and the learner
        # cannot tell which one.
        self.assertFalse(Observation(id="x", fidelity=0.90).usable)
        self.assertTrue(Observation(id="x", fidelity=0.95).usable)


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="imgbench-"))

    def test_records_only_observed_fields(self):
        record = store.record(
            Observation(id="m", measured_image=0.07, fidelity=1.0, samples=4), "2026-08-28"
        )
        self.assertEqual(
            set(record),
            {"date", "id", "measured_image", "fidelity", "samples", "discount", "quoted_image"},
        )
        # Derived judgements must not be persisted: a later change to the
        # usable threshold should re-rank old runs, not inherit a stale verdict.
        self.assertNotIn("usable", record)
        self.assertNotIn("cost_per_correct_image", record)

    def test_round_trip_and_latest_wins(self):
        path = store.history_path(self.tmp)
        store.append(path, [{"date": "2026-08-01", "id": "m", "measured_image": 0.05}])
        store.append(path, [{"date": "2026-08-28", "id": "m", "measured_image": 0.07}])
        latest = store.latest_by_model(store.read(path))
        self.assertEqual(latest["m"]["measured_image"], 0.07)

    def test_malformed_line_does_not_blind_the_log(self):
        path = store.history_path(self.tmp)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps({"date": "2026-08-01", "id": "m"}) + "\n{ truncated\n"
        )
        self.assertEqual(len(store.read(path)), 1)

    def test_movement_needs_two_observations(self):
        path = store.history_path(self.tmp)
        store.append(path, [{"date": "2026-08-01", "id": "m", "measured_image": 0.05}])
        before, now = store.movement(store.read(path), "m")
        self.assertIsNone(before)
        self.assertIsNotNone(now)

        store.append(path, [{"date": "2026-08-28", "id": "m", "measured_image": 0.07}])
        before, now = store.movement(store.read(path), "m")
        self.assertEqual(before["measured_image"], 0.05)
        self.assertEqual(now["measured_image"], 0.07)


if __name__ == "__main__":
    unittest.main()


class SuggestTests(unittest.TestCase):
    """`suggest` must under-suggest rather than manufacture confidence."""

    def test_cheaper_and_equally_faithful_wins(self):
        from catalog import dominates
        incumbent = Observation(id="dear", measured_image=0.069, fidelity=1.0)
        challenger = Observation(id="cheap", measured_image=0.040, fidelity=1.0)
        self.assertTrue(dominates(challenger, incumbent))

    def test_cheaper_but_less_faithful_never_wins(self):
        # The whole point. No discount offsets a wrong glyph.
        from catalog import dominates
        incumbent = Observation(id="good", measured_image=0.069, fidelity=1.0)
        challenger = Observation(id="bad", measured_image=0.039, fidelity=0.95)
        self.assertFalse(dominates(challenger, incumbent))

    def test_unmeasured_never_displaces_measured(self):
        # A catalog price is not evidence: it does not match the bill.
        from catalog import dominates
        incumbent = Observation(id="known", measured_image=0.069, fidelity=1.0)
        self.assertFalse(dominates(Observation(id="unknown"), incumbent))
        self.assertFalse(
            dominates(Observation(id="u", quoted_image=0.001), incumbent))

    def test_a_model_never_dominates_itself(self):
        from catalog import dominates
        same = Observation(id="x", measured_image=0.05, fidelity=1.0)
        self.assertFalse(dominates(same, same))

    def test_worth_measuring_lists_only_the_unknown(self):
        from catalog import ImageModel, worth_measuring
        catalog = [ImageModel(id="a"), ImageModel(id="b"), ImageModel(id="c")]
        observed = {"a": Observation(id="a", measured_image=0.05, fidelity=1.0)}
        incumbent = observed["a"]
        self.assertEqual(
            [m.id for m in worth_measuring(catalog, observed, incumbent)],
            ["b", "c"],
        )

    def test_price_moves_need_two_measured_observations(self):
        from catalog import price_moves
        history = [
            {"id": "m", "date": "2026-08-01", "measured_image": 0.05},
            {"id": "m", "date": "2026-09-01", "measured_image": 0.07},
            {"id": "once", "date": "2026-09-01", "measured_image": 0.02},
            # A catalog-only record is not news: that figure never matched the bill.
            {"id": "quoted", "date": "2026-08-01", "quoted_image": 0.001},
            {"id": "quoted", "date": "2026-09-01", "quoted_image": 0.002},
        ]
        moves = price_moves(history)
        self.assertEqual([m[0] for m in moves], ["m"])
        self.assertEqual(moves[0][1:3], (0.05, 0.07))

    def test_a_small_move_is_not_reported(self):
        from catalog import price_moves
        history = [
            {"id": "m", "date": "2026-08-01", "measured_image": 0.0690},
            {"id": "m", "date": "2026-09-01", "measured_image": 0.0691},
        ]
        self.assertEqual(price_moves(history), [])
