#!/usr/bin/env sh

# THIS SCRIPT HAS BEEN ADAPTED FROM
# https://github.com/KubeArmor/kubearmor-client/blob/main/install.sh

set -e

usage() {
  this=$1
  cat <<EOF
$this: download go binaries for knoxctl a.k.a accuknox-cli-v2

Usage: $this [-b] bindir [-d] [tag]
	-b sets bindir or installation directory, Defaults to ./bin
	-d turns on debug logging

	[tag] is a semver tag from -
	https://github.com/accuknox/knoxctl-website/releases

	[tag] might also be without the patch version.
	In this case latest patch version of the given release version
	will be fetched.
	Example: v0.4

	If tag is missing, then the latest will be used.

EOF
  exit 2
}

parse_args() {
  #BINDIR is ./bin unless set be ENV
  # over-ridden by flag below

  BINDIR=${BINDIR:-./bin}
  while getopts "b:dh?x" arg; do
    case "$arg" in
      b) BINDIR="$OPTARG" ;;
      d) log_set_priority 10 ;;
      h | \?) usage "$0" ;;
      x) set -x ;;
    esac
  done
  shift $((OPTIND - 1))
  TAG=$1
}

# this function wraps all the destructive operations
# if a curl|bash cuts off the end of the script due to
# network, either nothing will happen or will syntax error
# out preventing half-done work
execute() {
  tmpdir=$(mktemp -d $TMPDIR)
  log_debug "downloading files into ${tmpdir}"
  http_download "${tmpdir}/${TARBALL}" "${TARBALL_URL}"
  http_download "${tmpdir}/${CHECKSUM}" "${CHECKSUM_URL}"
  hash_sha256_verify "${tmpdir}/${TARBALL}" "${tmpdir}/${CHECKSUM}"
  srcdir="${tmpdir}"
  (cd "${tmpdir}" && untar "${TARBALL}")
  test ! -d "${BINDIR}" && install -d "${BINDIR}"
  for binexe in $BINARIES; do
    if [ "$OS" = "windows" ]; then
      binexe="${binexe}.exe"
    fi
    install "${srcdir}/${binexe}" "${BINDIR}/"
    log_info "installed ${BINDIR}/${binexe}"
    log_info "knoxctl is installed in ${BINDIR}"
    log_info "invoke ${BINDIR}/${binexe} or move knoxctl to your desired PATH"
  done
  rm -rf "${tmpdir}"
}

get_binaries() {
  case "$PLATFORM" in
    darwin/amd64) BINARIES="knoxctl" ;;
    darwin/arm64) BINARIES="knoxctl" ;;
    linux/amd64) BINARIES="knoxctl" ;;
    linux/arm64) BINARIES="knoxctl" ;;
    windows/amd64) BINARIES="knoxctl" ;;
    windows/arm64) BINARIES="knoxctl" ;;
    *)
      log_crit "platform $PLATFORM is not supported.  Make sure this script is up-to-date and file request at https://github.com/${PREFIX}/issues/new"
      exit 1
      ;;
  esac
}

# returns true if $1 is newer than $2
# false otherwsie
semver_compare() {
	V1_MAJOR=$(echo "$1"| cut -d'.' -f 1)
	V1_MINOR=$(echo "$1"| cut -d'.' -f 2)
	V1_PATCH=$(echo "$1"| cut -d'.' -f 3)

	V2_MAJOR=$(echo "$2"| cut -d'.' -f 1)
	V2_MINOR=$(echo "$2"| cut -d'.' -f 2)
	V2_PATCH=$(echo "$2"| cut -d'.' -f 3)

	if ([ "${V1_MAJOR}" -gt "${V2_MAJOR}" ]) || \
	([ "${V1_MAJOR}" -eq "${V2_MAJOR}" ] && [ "${V1_MINOR}" -gt "${V2_MINOR}" ]) || \
	([ "${V1_MAJOR}" -eq "${V2_MAJOR}" ] && [ "${V1_MINOR}" -eq "${V2_MINOR}" ] && [ "${V1_PATCH}" -ge "${V2_PATCH}" ]); then
		# true
		return 0
	fi

	# false
	return 1
}

get_patch_version() {
  owner_repo=$1
  tag=${2#v}
  giturl="https://api.github.com/repos/${owner_repo}/releases"
  json=$(http_copy "$giturl" "Accept:application/json")
  test -z "$json" && return 1
  version=$(echo $json | tr -s ',' '\n' | sed -n 's/.*"tag_name"\s*:\s*"\(.*'${tag}'.*\)"/\1/p' | head -n 1)
  test -z "$version" && return 1
  echo "$version"
}

tag_to_version() {
	if [ -z "${TAG}" ]; then
		# latest tag will always be fetched from GitHub
		# as this script is added with v0.3.0
		log_info "checking GitHub for latest tag"
	else
		# check GitHub only if provided tag greater than/equal to v0.3.0
		if semver_compare "${TAG#v}" "0.3.0"; then
			log_info "checking GitHub for tag '${TAG}'"

			# tag doesn't contain patch version
			temp_tag=${TAG#v}
			tag_length=${#temp_tag}
			if [[ $tag_length -le 3 ]]; then
				TAG=$(get_patch_version "$OWNER/$REPO" $TAG)
			fi

		else
			log_info "downloading from knoxctl.accuknox.com"
			# if version starts with 'v', remove it
			VERSION=${TAG#v}
			return
		fi
	fi

	REALTAG=$(github_release "$OWNER/$REPO" "${TAG}") && true

	if test -z "$REALTAG"; then
		log_crit "unable to find '${TAG}' - use 'latest' or see https://github.com/${PREFIX}/releases for details"
		exit 1
	fi
	# if version starts with 'v', remove it
	TAG="$REALTAG"
	VERSION=${TAG#v}
}

adjust_format() {
  # change format (tar.gz or zip) based on OS
  true
}

adjust_os() {
  # adjust archive name based on OS
  true
}

adjust_arch() {
  # adjust archive name based on ARCH
  true
}

cat /dev/null <<EOF
------------------------------------------------------------------------
https://github.com/client9/shlib - portable posix shell functions
Public domain - http://unlicense.org
https://github.com/client9/shlib/blob/master/LICENSE.md
but credit (and pull requests) appreciated.
------------------------------------------------------------------------
EOF
is_command() {
  command -v "$1" >/dev/null
}
echoerr() {
  echo "$@" 1>&2
}
log_prefix() {
  echo "$0"
}
_logp=6
log_set_priority() {
  _logp="$1"
}
log_priority() {
  if test -z "$1"; then
    echo "$_logp"
    return
  fi
  [ "$1" -le "$_logp" ]
}
log_tag() {
  case $1 in
    0) echo "emerg" ;;
    1) echo "alert" ;;
    2) echo "crit" ;;
    3) echo "err" ;;
    4) echo "warning" ;;
    5) echo "notice" ;;
    6) echo "info" ;;
    7) echo "debug" ;;
    *) echo "$1" ;;
  esac
}
log_debug() {
  log_priority 7 || return 0
  echoerr "$(log_prefix)" "$(log_tag 7)" "$@"
}
log_info() {
  log_priority 6 || return 0
  echoerr "$(log_prefix)" "$(log_tag 6)" "$@"
}
log_err() {
  log_priority 3 || return 0
  echoerr "$(log_prefix)" "$(log_tag 3)" "$@"
}
log_crit() {
  log_priority 2 || return 0
  echoerr "$(log_prefix)" "$(log_tag 2)" "$@"
}
uname_os() {
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$os" in
    cygwin_nt*) os="windows" ;;
    mingw*) os="windows" ;;
    msys_nt*) os="windows" ;;
  esac
  echo "$os"
}
uname_arch() {
  arch=$(uname -m)
  case $arch in
    x86_64) arch="amd64" ;;
    x86) arch="386" ;;
    i686) arch="386" ;;
    i386) arch="386" ;;
    aarch64) arch="arm64" ;;
    armv5*) arch="armv5" ;;
    armv6*) arch="armv6" ;;
    armv7*) arch="armv7" ;;
  esac
  echo ${arch}
}
uname_os_check() {
  os=$(uname_os)
  case "$os" in
    darwin) return 0 ;;
    dragonfly) return 0 ;;
    freebsd) return 0 ;;
    linux) return 0 ;;
    android) return 0 ;;
    nacl) return 0 ;;
    netbsd) return 0 ;;
    openbsd) return 0 ;;
    plan9) return 0 ;;
    solaris) return 0 ;;
    windows) return 0 ;;
  esac
  log_crit "uname_os_check '$(uname -s)' got converted to '$os' which is not a GOOS value. Please file bug at https://github.com/client9/shlib"
  return 1
}
uname_arch_check() {
  arch=$(uname_arch)
  case "$arch" in
    386) return 0 ;;
    amd64) return 0 ;;
    arm64) return 0 ;;
    armv5) return 0 ;;
    armv6) return 0 ;;
    armv7) return 0 ;;
    ppc64) return 0 ;;
    ppc64le) return 0 ;;
    mips) return 0 ;;
    mipsle) return 0 ;;
    mips64) return 0 ;;
    mips64le) return 0 ;;
    s390x) return 0 ;;
    amd64p32) return 0 ;;
  esac
  log_crit "uname_arch_check '$(uname -m)' got converted to '$arch' which is not a GOARCH value.  Please file bug report at https://github.com/client9/shlib"
  return 1
}
untar() {
  tarball=$1
  case "${tarball}" in
    *.tar.gz | *.tgz) tar --no-same-owner -xzf "${tarball}" ;;
    *.tar) tar --no-same-owner -xf "${tarball}" ;;
    *.zip) unzip "${tarball}" ;;
    *)
      log_err "untar unknown archive format for ${tarball}"
      return 1
      ;;
  esac
}
http_download_curl() {
  local_file=$1
  source_url=$2
  header=$3
  if [ -z "$header" ]; then
    code=$(curl -w '%{http_code}' -sL -o "$local_file" "$source_url")
  else
    code=$(curl -w '%{http_code}' -sL -H "$header" -o "$local_file" "$source_url")
  fi
  if [ "$code" != "200" ]; then
    log_debug "http_download_curl received HTTP status $code"
    return 1
  fi
  return 0
}
http_download_wget() {
  local_file=$1
  source_url=$2
  header=$3
  if [ -z "$header" ]; then
    wget -q -O "$local_file" "$source_url"
  else
    wget -q --header "$header" -O "$local_file" "$source_url"
  fi
}
http_download() {
  log_debug "http_download $2"
  if is_command curl; then
    http_download_curl "$@"
    return
  elif is_command wget; then
    http_download_wget "$@"
    return
  fi
  log_crit "http_download unable to find wget or curl"
  return 1
}

http_copy() {
  tmp=$(mktemp $TMPDIR)
  http_download "${tmp}" "$1" "$2" || return 1
  body=$(cat "$tmp")
  rm -f "${tmp}"
  echo "$body"
}

github_release() {
  owner_repo=$1
  version=$2
  test -z "$version" && version="latest"
  giturl="https://github.com/${owner_repo}/releases/${version}"
  json=$(http_copy "$giturl" "Accept:application/json")
  test -z "$json" && return 1
  version=$(echo "$json" | tr -s '\n' ' ' | sed 's/.*"tag_name":"//' | sed 's/".*//')
  test -z "$version" && return 1
  echo "$version"
}

hash_sha256() {
  TARGET=${1:-/dev/stdin}
  if is_command gsha256sum; then
    hash=$(gsha256sum "$TARGET") || return 1
    echo "$hash" | cut -d ' ' -f 1
  elif is_command sha256sum; then
    hash=$(sha256sum "$TARGET") || return 1
    echo "$hash" | cut -d ' ' -f 1
  elif is_command shasum; then
    hash=$(shasum -a 256 "$TARGET" 2>/dev/null) || return 1
    echo "$hash" | cut -d ' ' -f 1
  elif is_command openssl; then
    hash=$(openssl -dst openssl dgst -sha256 "$TARGET") || return 1
    echo "$hash" | cut -d ' ' -f a
  else
    log_crit "hash_sha256 unable to find command to compute sha-256 hash"
    return 1
  fi
}

hash_sha256_verify() {
  TARGET=$1
  checksums=$2
  if [ -z "$checksums" ]; then
    log_err "hash_sha256_verify checksum file not specified in arg2"
    return 1
  fi
  BASENAME=${TARGET##*/}
  want=$(grep "${BASENAME}" "${checksums}" 2>/dev/null | tr '\t' ' ' | cut -d ' ' -f 1)
  if [ -z "$want" ]; then
    log_err "hash_sha256_verify unable to find checksum for '${TARGET}' in '${checksums}'"
    return 1
  fi
  got=$(hash_sha256 "$TARGET")
  if [ "$want" != "$got" ]; then
    log_err "hash_sha256_verify checksum for '$TARGET' did not verify ${want} vs $got"
    return 1
  fi
}

# Use /tmp/ as temp directory if write access available else use current
# working directory.
# [Background]:
# A curl installed using snap does not have permissions to write to
# /tmp/ directory since snap requires apps to use their own directories to write
# temp file and not use system wide /tmp dir. However, a curl installed using apt
# or other package mgmt tool can write to /tmp/ dir.
# Ref: https://github.com/kubearmor/kubearmor-client/pull/490
get_temp_dir() {
  tmpf=$(mktemp -d)
  if [ ! -z "$tmpf" ]; then
	TMPDIR="-p $PWD"
  else
    rm -f $tmpf
  fi
}

cat /dev/null <<EOF
------------------------------------------------------------------------
End of functions from https://github.com/client9/shlib
------------------------------------------------------------------------
EOF


PROJECT_NAME="knoxctl"
OWNER=accuknox
REPO="knoxctl-website"
BINARY=knoxctl
FORMAT=tar.gz
OS=$(uname_os)
ARCH=$(uname_arch)
PREFIX="$OWNER/$REPO"

# use in logging routines
log_prefix() {
	echo "$PREFIX"
}
PLATFORM="${OS}/${ARCH}"

S3_DOWNLOAD="https://knoxctl.accuknox.com/binaries"
GITHUB_DOWNLOAD="https://github.com/${OWNER}/${REPO}/releases/download"
get_temp_dir

uname_os_check "$OS"
uname_arch_check "$ARCH"

parse_args "$@"

get_binaries

tag_to_version

adjust_format

adjust_os

adjust_arch

log_info "found version: ${VERSION} for ${TAG}/${OS}/${ARCH}"

NAME=${PROJECT_NAME}_${VERSION}_${OS}_${ARCH}
TARBALL=${NAME}.${FORMAT}
CHECKSUM=${PROJECT_NAME}_${VERSION}_checksums.txt

if semver_compare "${VERSION}" "0.3.0";
then
	# version greater than/equal to 0.3.0 download from github releases
	TARBALL_URL=${GITHUB_DOWNLOAD}/${TAG}/${TARBALL}
	CHECKSUM_URL=${GITHUB_DOWNLOAD}/${TAG}/${CHECKSUM}
else
	# download from s3
	TARBALL_URL=${S3_DOWNLOAD}/${TARBALL}
	CHECKSUM_URL=${S3_DOWNLOAD}/${CHECKSUM}
fi

execute
