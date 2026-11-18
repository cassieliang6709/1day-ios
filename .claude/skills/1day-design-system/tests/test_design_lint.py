"""python3 -m unittest discover -s .claude/skills/1day-design-system/tests"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import design_lint  # noqa: E402


class DesignLintTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.views = self.root / "ios/AISetlog/Views"
        (self.views / "Plans").mkdir(parents=True)
        (self.views / "DesignSystem").mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text):
        (self.views / rel).write_text(text, encoding="utf-8")

    def test_counts_each_kind_and_skips_tokens_comments_and_allowed_lines(self):
        self.write("Plans/Card.swift", "\n".join([
            'Text("a").font(.system(size: 13))',
            'RoundedRectangle(cornerRadius: 16)',
            '.padding(.horizontal, 20)',
            '.padding(12)',
            'VStack(spacing: 8) {}',
            'Color(hex: 0xFFFFFF)',
            'Text("b").font(OneDay.Font.caption)',
            'RoundedRectangle(cornerRadius: OneDay.Radius.card)',
            '// .system(size: 99) in a comment',
            'Text("c").font(.system(size: 80)) // design-lint: allow',
        ]))
        self.write("DesignSystem/Tokens.swift", 'Text("x").font(.system(size: 13))')

        counts = design_lint.scan(self.views)

        self.assertEqual(list(counts), ["Plans/Card.swift"])
        self.assertEqual(counts["Plans/Card.swift"],
                         {"font": 1, "radius": 1, "padding": 2, "spacing": 1, "hex": 1})

    def test_baseline_fails_only_when_a_file_gets_worse(self):
        self.write("Plans/Card.swift", ".font(.system(size: 13))\n.font(.system(size: 15))")
        baseline = self.root / "baseline.json"
        self.assertEqual(design_lint.main(["--root", str(self.root), "--write-baseline", str(baseline)]), 0)

        self.write("Plans/Card.swift", ".font(.system(size: 13))")
        self.assertEqual(design_lint.main(["--root", str(self.root), "--baseline", str(baseline)]), 0)

        self.write("Plans/New.swift", "RoundedRectangle(cornerRadius: 9)")
        self.assertEqual(design_lint.main(["--root", str(self.root), "--baseline", str(baseline)]), 1)
        worse = design_lint.regressions(design_lint.scan(self.views), json.loads(baseline.read_text()))
        self.assertEqual(worse, ["Plans/New.swift: radius 0 -> 1"])

    def test_missing_views_is_a_usage_error(self):
        self.assertEqual(design_lint.main(["--root", str(self.root / "nowhere")]), 2)


if __name__ == "__main__":
    unittest.main()
