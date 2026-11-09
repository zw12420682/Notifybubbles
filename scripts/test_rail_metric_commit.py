"""Invalid split measurements must never overwrite a previously valid cache."""
from pathlib import Path
s = (Path(__file__).resolve().parents[1] / 'Sources/NFBManager.m').read_text()
a = s.index('BOOL validRailMeasurement =')
b = s.index('if (splitNow && validRailMeasurement)', a)
c = s.index('[self persistRailMetricIfMeasured:railMeasuredNow];', b)
assert 'NFBSplitMetricsValid(plan.diameter' in s[a:b]
assert 'isfinite(plan.toggleTop)' in s[a:b]
assert 'self.splitRailDiameter = plan.diameter;' in s[b:c]
assert 'railMeasuredNow = YES;' in s[b:c]
assert 'if (splitNow && plan.toggleTop > 0)' not in s
print('PASS: split cache only commits a validated measurement')
