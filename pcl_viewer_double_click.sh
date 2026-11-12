#!/usr/bin/env bash
# 在 Ubuntu 上安装 pcl-tools，并让双击 .pcd 执行：
#   pcl_viewer <文件> -ax 3
# 文件图标继续使用系统里 .pcd 默认的紫色图像图标（image-x-generic），
# 不另行绘制或替换图标。
set -euo pipefail

die() {
  echo "错误：$*" >&2
  exit 1
}

if [[ $# -ne 0 ]]; then
  die "此脚本不需要参数，直接运行即可。"
fi

if [[ "$(id -u)" -eq 0 ]]; then
  die "请用普通用户运行。需要安装软件时，脚本会自己调用 sudo。"
fi

if [[ ! -r /etc/os-release ]]; then
  die "无法读取 /etc/os-release，此脚本仅支持 Ubuntu。"
fi

# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  die "此脚本仅支持 Ubuntu，当前系统为：${PRETTY_NAME:-未知}。"
fi

if ! command -v sudo >/dev/null 2>&1; then
  die "未找到 sudo，无法安装 pcl-tools。"
fi

DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
MIME_ROOT="${DATA_HOME}/mime"
MIME_PKG_DIR="${MIME_ROOT}/packages"
APP_DIR="${DATA_HOME}/applications"
MIME_PKG="${MIME_PKG_DIR}/pcl-pcd.xml"
DESKTOP_FILE="${APP_DIR}/pcl-viewer.desktop"
DESKTOP_NAME="pcl-viewer.desktop"

echo "正在安装 pcl-tools 以及 MIME / 桌面文件工具……"
# sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  pcl-tools \
  shared-mime-info \
  xdg-utils \
  desktop-file-utils

if [[ -x /usr/bin/pcl_viewer ]]; then
  viewer=/usr/bin/pcl_viewer
else
  viewer="$(command -v pcl_viewer || true)"
fi
if [[ -z "${viewer}" || ! -x "${viewer}" ]]; then
  die "pcl-tools 已安装，但找不到可执行的 pcl_viewer。"
fi

# 未配置时，*.pcd 属于 image/x-photo-cd，文件管理器显示的是
# 图标主题中的 image-x-generic。Ubuntu 默认的 Yaru 主题里，
# 这就是紫色的通用图像图标。这里只确认系统里确实有它，
# 配置时按图标名引用，以便跟随主题提供的各个尺寸。
locate_default_pcd_icon() {
  local theme="" root candidate size
  local -a roots=()

  if command -v gsettings >/dev/null 2>&1; then
    theme="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || true)"
    theme="${theme//\'/}"
  fi

  if [[ -n "${theme}" ]]; then
    roots+=("/usr/share/icons/${theme}")
    roots+=("${DATA_HOME}/icons/${theme}")
  fi
  roots+=(
    /usr/share/icons/Yaru
    /usr/share/icons/Humanity
    /usr/share/icons/Adwaita
    /usr/share/icons/hicolor
  )

  for root in "${roots[@]}"; do
    [[ -d "${root}" ]] || continue
    for size in 256x256 128x128 64x64 48x48 scalable 32x32 24x24 22x22 16x16; do
      for candidate in \
        "${root}/${size}/mimetypes/image-x-generic.png" \
        "${root}/${size}/mimetypes/image-x-generic.svg" \
        "${root}/${size}@2x/mimetypes/image-x-generic.png" \
        "${root}/mimes/${size%%x*}/image-x-generic.svg"
      do
        if [[ -f "${candidate}" ]]; then
          printf '%s\n' "${candidate}"
          return 0
        fi
      done
    done
    candidate="$(find "${root}" -type f \
      \( -name 'image-x-generic.png' -o -name 'image-x-generic.svg' \) \
      ! -name '*symbolic*' -print -quit 2>/dev/null || true)"
    if [[ -n "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

icon_file="$(locate_default_pcd_icon || true)"
if [[ -z "${icon_file}" ]]; then
  die "在 /usr/share/icons 中找不到 .pcd 默认使用的 image-x-generic 图标。"
fi
echo "将继续使用系统默认的 PCD 图标：${icon_file}"

mkdir -p "${MIME_PKG_DIR}" "${APP_DIR}"

# weight 高于系统里 image/x-photo-cd 的 *.pcd（默认 50），
# 这样点云文件会归到 application/x-pcd。
# icon / generic-icon 都指向 image-x-generic，避免变成普通文档图标。
cat > "${MIME_PKG}" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-pcd">
    <comment>PCL Point Cloud Data</comment>
    <comment xml:lang="zh_CN">PCL 点云数据</comment>
    <sub-class-of type="application/octet-stream"/>
    <icon name="image-x-generic"/>
    <generic-icon name="image-x-generic"/>
    <glob pattern="*.pcd" weight="80"/>
  </mime-type>
</mime-info>
EOF

# pcl_viewer 的参数顺序是：文件在前，选项在后。
# 双击单个文件时等价于：pcl_viewer <文件> -ax 3
# %F 在多选打开时会带上其余文件，仍然位于 -ax 3 之前。
cat > "${DESKTOP_FILE}" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=PCL Viewer
Name[zh_CN]=PCL 点云查看器
Comment=Open a PCD file with pcl_viewer
Comment[zh_CN]=使用 pcl_viewer 打开 PCD 点云
TryExec=${viewer}
Exec=${viewer} %F -ax 3
Icon=image-x-generic
Terminal=false
StartupNotify=false
NoDisplay=false
MimeType=application/x-pcd;image/x-photo-cd;
Categories=Graphics;Viewer;
EOF

update-mime-database "${MIME_ROOT}"
update-desktop-database "${APP_DIR}"
desktop-file-validate "${DESKTOP_FILE}"

# application/x-pcd：本脚本注册的点云类型。
# image/x-photo-cd：Ubuntu 对 *.pcd 的原始类型。两种识别结果都用同一个查看器，
# 原始类型的图标本来就是 image-x-generic，不会被改掉。
xdg-mime default "${DESKTOP_NAME}" application/x-pcd
xdg-mime default "${DESKTOP_NAME}" image/x-photo-cd

# 空文件会被内容嗅探成 text/plain，这里写入一行 PCD 头，
# 让校验按扩展名走到 application/x-pcd。
probe="$(mktemp --suffix=.pcd)"
printf '# .PCD v0.7 - Point Cloud Data file format\n' > "${probe}"
cleanup() {
  rm -f "${probe:-}"
}
trap cleanup EXIT

filetype="$(xdg-mime query filetype "${probe}")"
default_pcd="$(xdg-mime query default application/x-pcd || true)"
default_photo="$(xdg-mime query default image/x-photo-cd || true)"

if [[ "${filetype}" != "application/x-pcd" ]]; then
  die "校验失败：.pcd 被识别为 ${filetype:-空}，而不是 application/x-pcd。"
fi
if [[ "${default_pcd}" != "${DESKTOP_NAME}" || "${default_photo}" != "${DESKTOP_NAME}" ]]; then
  die "校验失败：默认打开方式未指向 ${DESKTOP_NAME}。"
fi

if command -v gio >/dev/null 2>&1; then
  icon_names="$(gio info -a standard::icon "${probe}" 2>/dev/null | sed -n 's/^[[:space:]]*standard::icon:[[:space:]]*//p' || true)"
  case "${icon_names}" in
    image-x-generic*|*" image-x-generic"*)
      ;;
    *)
      die "校验失败：.pcd 图标不是 image-x-generic（当前为：${icon_names:-空}）。"
      ;;
  esac
fi

echo "配置完成。"
echo "双击 .pcd 将执行：${viewer} <文件> -ax 3"
echo "图标仍使用系统的 image-x-generic（${icon_file}）。"
echo "若文件管理器里图标或打开方式没有马上更新，重新打开该文件夹即可。"
