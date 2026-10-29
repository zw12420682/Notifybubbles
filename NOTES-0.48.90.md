# 0.48.90 delivery notes

- 0.48.90 is a single-purpose fix on top of 0.48.88 (commit e8d827f): rapid
  keyboard show/hide no longer resubmits the column slide.
- Run 40892042653 (exact 9975f10) failed only in the test job's iOS simulator
  step: "automatic page roundtrip restores exact original page" (moves=1,
  actual {0,0}, expected {402,0}). NFBDesktopHost.m and DesktopHostTests.m are
  untouched by 0.48.90 (identical to e8d827f) and the test/assert are not
  relaxed; the same step passed on 0.48.88/d1b1042/0b03316.
- No functional source change in this follow-up commit; it only re-runs CI on
  the same tree (markdown-only commits are paths-ignored, hence the touch).
  The version stays 0.48.90.
