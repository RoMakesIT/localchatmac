"""Isolated retrieval regressions; no Chroma database or embedding download.

Run with: python3 -m unittest discover -s MemoryService -p 'test_*.py'
The service class is loaded from its source without executing app startup or
importing optional dependencies. SearchResult is represented by the same fields
on a lightweight namespace; the API's existing Pydantic model is unchanged.
"""

import ast
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock


def load_service_class():
    source = ast.parse(Path(__file__).with_name("app.py").read_text())
    service_class = next(
        node for node in source.body if isinstance(node, ast.ClassDef) and node.name == "MemoryService"
    )
    module = ast.Module(
        body=[ast.ImportFrom(module="__future__", names=[ast.alias(name="annotations")], level=0), service_class],
        type_ignores=[],
    )
    namespace = {"SearchResult": SimpleNamespace}
    exec(compile(ast.fix_missing_locations(module), "app.py", "exec"), namespace)
    return namespace["MemoryService"]


class FakeCollection:
    """Rank only candidates admitted by a Chroma-like scope filter."""

    def __init__(self, records):
        self.records = records
        self.queries = []

    def get(self, *, where=None, include):
        records = self.records
        if where is not None:
            records = [row for row in records if (row["metadata"] or {}).get("project_id") == where["project_id"]]
        return {
            "ids": [row["id"] for row in records],
            "metadatas": [row["metadata"] for row in records] if "metadatas" in include else [],
        }

    def query(self, *, query_embeddings, n_results, include, where=None, ids=None):
        self.queries.append({"where": where, "ids": ids, "n_results": n_results})
        records = self.records
        if where is not None:
            records = [row for row in records if (row["metadata"] or {}).get("project_id") == where["project_id"]]
        if ids is not None:
            records = [row for row in records if row["id"] in ids]
        # Rank after scoping. Global ranking first reproduces the old defect.
        records = sorted(records, key=lambda row: row["distance"])[:n_results]
        return {
            "ids": [[row["id"] for row in records]],
            "metadatas": [[row["metadata"] for row in records]],
            "documents": [[row["document"] for row in records]],
            "distances": [[row["distance"] for row in records]],
        }


def record(memory_id, project_id, distance):
    metadata = {
        "conversation_id": "conversation-" + memory_id,
        "timestamp": "2026-10-10T00:00:00+00:00",
        "user_message": "Question " + memory_id,
        "assistant_reply": "Answer " + memory_id,
    }
    if project_id is not None:
        metadata["project_id"] = project_id
    return {"id": memory_id, "metadata": metadata, "document": " Memory " + memory_id + " ", "distance": distance}


class MemorySearchTests(unittest.TestCase):
    service_class = load_service_class()

    def service(self, records):
        service = self.service_class.__new__(self.service_class)
        service.collection = FakeCollection(records)
        service._embed = Mock(return_value=[1.0, 0.0])
        return service

    def test_other_projects_cannot_crowd_out_requested_project(self):
        records = [record("foreign-" + str(index), "other", index / 1000) for index in range(75)]
        records += [record("local-second", "tax", 2.0), record("local-first", "tax", 1.0)]
        service = self.service(records)

        hits = service.search("profit", top_k=4, project_id="tax")

        self.assertEqual([hit.id for hit in hits], ["local-first", "local-second"])
        self.assertEqual(service.collection.queries[0]["where"], {"project_id": "tax"})
        self.assertEqual(service.collection.queries[0]["n_results"], 2)

    def test_empty_scope_skips_embedding_and_query_even_when_other_projects_exist(self):
        service = self.service([record("foreign", "other", 0.0)])

        self.assertEqual(service.search("profit", top_k=4, project_id="tax"), [])
        service._embed.assert_not_called()
        self.assertEqual(service.collection.queries, [])

    def test_global_scope_preserves_legacy_memories_without_other_project_leakage(self):
        service = self.service([
            record("foreign", "tax", 0.0),
            record("legacy-global", None, 0.1),
            record("explicit-global", "__global__", 0.2),
        ])

        hits = service.search("question", top_k=4, project_id="__global__")

        self.assertEqual([hit.id for hit in hits], ["legacy-global", "explicit-global"])
        self.assertTrue(all(hit.project_id == "__global__" for hit in hits))
        self.assertEqual(set(service.collection.queries[0]["ids"]), {"legacy-global", "explicit-global"})

    def test_named_project_does_not_receive_global_or_legacy_memories(self):
        service = self.service([
            record("legacy-global", None, 0.0),
            record("explicit-global", "__global__", 0.1),
            record("local", "tax", 0.2),
        ])

        hits = service.search("question", top_k=4, project_id="tax")

        self.assertEqual([hit.id for hit in hits], ["local"])

    def test_top_k_and_response_fields_remain_compatible(self):
        service = self.service([record("first", "tax", 0.1), record("second", "tax", 0.2)])

        hits = service.search("question", top_k=1, project_id="tax")

        self.assertEqual(len(hits), 1)
        self.assertEqual(vars(hits[0]), {
            "id": "first",
            "conversation_id": "conversation-first",
            "timestamp": "2026-10-10T00:00:00+00:00",
            "snippet": "Memory first",
            "user_message": "Question first",
            "assistant_reply": "Answer first",
            "distance": 0.1,
            "project_id": "tax",
        })


if __name__ == "__main__":
    unittest.main()
