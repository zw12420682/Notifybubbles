from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
p=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())
base={'items': [{'cell': 'PSSwitchCell', 'label': '启用悬浮气泡', 'key': 'Enabled', 'default': True, 'defaults': 'local.notifybubbles'}, {'cell': 'PSSwitchCell', 'label': '主屏显示', 'key': 'ShowOnHome', 'default': True, 'defaults': 'local.notifybubbles'}, {'cell': 'PSSwitchCell', 'label': 'App 内显示', 'key': 'ShowInApps', 'default': True, 'defaults': 'local.notifybubbles'}, {'cell': 'PSSliderCell', 'label': '分屏打开后校正总时长（秒）', 'key': 'SplitPlacementWindow', 'defaults': 'local.notifybubbles', 'default': 0.35, 'min': 0.0, 'max': 1.0, 'showValue': True}, {'cell': 'PSSliderCell', 'label': '键盘收起后检查延迟（秒）', 'key': 'KeyboardRecheckDelay', 'defaults': 'local.notifybubbles', 'default': 0.1, 'min': 0.0, 'max': 0.5, 'showValue': True}, {'cell': 'PSButtonCell', 'label': '清除全部气泡', 'action': 'clearBubbles'}, {'cell': 'PSSwitchCell', 'label': '切换时关闭上一个竖屏窗口', 'key': 'ClosePreviousSplit', 'default': True, 'defaults': 'local.notifybubbles'}, {'cell': 'PSSwitchCell', 'label': '截屏隐藏气泡', 'key': 'HideInScreenshots', 'default': False, 'defaults': 'local.notifybubbles'}, {'cell': 'PSButtonCell', 'label': '选择常用 App', 'action': 'chooseFavorites'}, {'cell': 'PSSwitchCell', 'label': '热点无连接时自动关闭', 'key': 'HotspotAutoClose', 'default': False, 'defaults': 'local.notifybubbles'}, {'cell': 'PSSliderCell', 'label': '无连接等待时间（分钟）', 'key': 'HotspotIdleMinutes', 'default': 5, 'min': 1, 'max': 60, 'showValue': True, 'defaults': 'local.notifybubbles'}, {'cell': 'PSSwitchCell', 'label': '调试日志', 'key': 'DebugLogging', 'default': False, 'defaults': 'local.notifybubbles'}, {'cell': 'PSButtonCell', 'label': '采样 ARC 层级（24 秒）', 'action': 'captureArcHierarchy'}]}
def controls(p):return {x.get('key') or x.get('action'):x for x in p['items'] if x.get('cell')!='PSGroupCell'}
assert controls(p)==controls(base),'Changing grouping must not change any setting/action contract'
a=[x for x in p['items'] if x.get('cell')!='PSGroupCell']
assert len(a)==13 and len(controls(p))==13
assert next(x for x in a if x.get('key'))['key']=='Enabled'
for old in ['最近 3 个后台','双击分屏房子','启用电影模式','不使用双击']:
 assert old not in str(p)
print('PASS: settings rearrangement preserves all 10 keys and 3 actions, defaults, ranges and domains')
