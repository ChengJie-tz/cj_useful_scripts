#!/usr/bin/env bash
# 在新的 Ubuntu 上安装并配置雾凇拼音（fcitx5 + rime-ice）。
# 用法：bash setup-fcitx5-rime-ice.sh
# 跑完后注销并重新登录。
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "请用普通用户运行，不要用 sudo 或 root。" >&2
  exit 1
fi

RIME_DIR="${HOME}/.local/share/fcitx5/rime"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

echo "==> 安装软件包"
# sudo apt-get update
sudo apt-get install -y \
  fcitx5 \
  fcitx5-rime \
  fcitx5-config-qt \
  fcitx5-frontend-gtk3 \
  fcitx5-frontend-gtk4 \
  fcitx5-frontend-qt5 \
  im-config \
  librime-bin \
  git \
  unzip \
  wget \
  ca-certificates

echo "==> 停用 ibus（不卸载软件包，GNOME 还依赖它）"
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user mask --now org.freedesktop.IBus.session.GNOME.service || true
  systemctl --user mask --now org.freedesktop.IBus.session.generic.service || true
fi
pkill -u "${USER}" -x ibus-daemon || true
pkill -u "${USER}" -x fcitx5 || true

im-config -n fcitx5

mkdir -p "${HOME}/.config/environment.d"
cat > "${HOME}/.config/environment.d/fcitx5.conf" << 'EOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF

cat > "${HOME}/.pam_environment" << 'EOF'
GTK_IM_MODULE DEFAULT=fcitx
QT_IM_MODULE DEFAULT=fcitx
XMODIFIERS DEFAULT=@im=fcitx
EOF

if command -v gsettings >/dev/null 2>&1; then
  python3 - << 'PY' || echo "跳过 GNOME 输入源设置（当前没有图形会话配置）。"
import ast
import subprocess

raw = subprocess.check_output(
    ["gsettings", "get", "org.gnome.desktop.input-sources", "sources"],
    text=True,
).strip()
try:
    sources = ast.literal_eval(raw)
except (SyntaxError, ValueError):
    sources = []
kept = [item for item in sources if not (isinstance(item, tuple) and item and item[0] == "ibus")]
if not kept:
    kept = [("xkb", "us")]
literal = repr(kept).replace('"', "'")
subprocess.check_call(
    ["gsettings", "set", "org.gnome.desktop.input-sources", "sources", literal]
)
print("GNOME 输入源已去掉 ibus：", literal)
PY
fi

echo "==> 安装雾凇拼音"
mkdir -p "$(dirname "${RIME_DIR}")"
if [[ -d "${RIME_DIR}/.git" ]]; then
  git -C "${RIME_DIR}" pull --ff-only || true
elif [[ ! -f "${RIME_DIR}/rime_ice.schema.yaml" ]]; then
  if [[ -e "${RIME_DIR}" ]]; then
    mv "${RIME_DIR}" "${RIME_DIR}.bak-$(date +%Y%m%d-%H%M%S)"
  fi
  if ! git clone --depth 1 https://github.com/iDvel/rime-ice.git "${RIME_DIR}"; then
    echo "GitHub 克隆失败，改用镜像压缩包。"
    mkdir -p "${RIME_DIR}"
    tmpzip="$(mktemp /tmp/rime-ice.XXXXXX.zip)"
    wget -O "${tmpzip}" https://mirror.nju.edu.cn/github-release/iDvel/rime-ice/LatestRelease/full.zip
    unzip -o "${tmpzip}" -d "${RIME_DIR}"
    rm -f "${tmpzip}"
    if [[ -f "${RIME_DIR}/full/rime_ice.schema.yaml" ]]; then
      mv "${RIME_DIR}/full/"* "${RIME_DIR}/"
      rmdir "${RIME_DIR}/full" || true
    fi
  fi
fi

if [[ -d "${RIME_DIR}/others/no_lua_schema" ]]; then
  cp -a "${RIME_DIR}/others/no_lua_schema/." "${RIME_DIR}/"
else
  echo "找不到 others/no_lua_schema，无法换成无 Lua 方案。" >&2
  exit 1
fi

python3 - "${RIME_DIR}/rime_ice.schema.yaml" << 'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
pattern = re.compile(
    r"(^  - name: ascii_mode\n    states:.*\n)(?!    reset:)",
    re.M,
)
new, count = pattern.subn(r"\1    reset: 1\n", text, count=1)
if count != 1 and "name: ascii_mode" not in text:
    sys.exit("rime_ice.schema.yaml 里没有 ascii_mode，无法设置默认英文。")
path.write_text(new, encoding="utf-8")
PY

echo "==> 写入 fcitx5 配置"
mkdir -p "${HOME}/.config/fcitx5/conf" "${HOME}/.config/autostart"

cat > "${HOME}/.config/fcitx5/config" << 'EOF'
[Hotkey]
EnumerateWithTriggerKeys=True
EnumerateSkipFirst=False

[Hotkey/TriggerKeys]
0=Control+space
1=Zenkaku_Hankaku
2=Hangul

[Hotkey/AltTriggerKeys]
# 0=Shift_L

[Hotkey/EnumerateForwardKeys]
0=Control+Shift_L

[Hotkey/EnumerateBackwardKeys]
0=Control+Shift_R

[Hotkey/EnumerateGroupForwardKeys]
0=Super+space

[Hotkey/EnumerateGroupBackwardKeys]
0=Shift+Super+space

[Hotkey/ActivateKeys]
0=Hangul_Hanja

[Hotkey/DeactivateKeys]
0=Hangul_Romaja

[Hotkey/PrevPage]
0=Up

[Hotkey/NextPage]
0=Down

[Hotkey/PrevCandidate]
0=Shift+Tab

[Hotkey/NextCandidate]
0=Tab

[Hotkey/TogglePreedit]
0=Control+Alt+P

[Behavior]
ActiveByDefault=True
ShareInputState=No
PreeditEnabledByDefault=True
ShowInputMethodInformation=True
showInputMethodInformationWhenFocusIn=False
CompactInputMethodInformation=True
ShowFirstInputMethodInformation=True
DefaultPageSize=5
OverrideXkbOption=False
CustomXkbOption=
EnabledAddons=
DisabledAddons=kimpanel
PreloadInputMethod=True
EOF

cat > "${HOME}/.config/fcitx5/conf/classicui.conf" << 'EOF'
Vertical Candidate List=False
PerScreenDPI=True
WheelForPaging=True
Font="Sans Serif 13"
MenuFont="Sans 10"
TrayFont="Sans Bold 10"
TrayOutlineColor=#000000
TrayTextColor=#ffffff
PreferTextIcon=False
ShowLayoutNameInIcon=True
UseInputMethodLangaugeToDisplayText=True
Theme=default
EOF

printf '%s\n' 'PreeditInApplication=False' > "${HOME}/.config/fcitx5/conf/rime.conf"

cat > "${HOME}/.config/fcitx5/profile" << 'EOF'
[Groups/0]
Name=默认
Default Layout=us
DefaultIM=rime

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=rime
Layout=

[GroupOrder]
0=默认
EOF

if [[ -f /usr/share/applications/org.fcitx.Fcitx5.desktop ]]; then
  cp -a /usr/share/applications/org.fcitx.Fcitx5.desktop "${HOME}/.config/autostart/"
fi

echo "==> 编译词库"
rime_deployer --build "${RIME_DIR}" /usr/share/rime-data "${RIME_DIR}/build"

echo
echo "安装完成。请注销并重新登录。"
echo "新窗口默认英文，按一次左 Shift 进入中文，再按一次回到英文。"
echo "拼音显示在候选框里。不要用 Ctrl+空格代替这次中英文切换。"