#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

source ./update.sh

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
	# exclude vendor directory
	tmp=()
	for value in "${versions[@]}"; do
		if [ "$value" != "vendor/" ]; then
			tmp+=($value)
		fi
	done
	versions=("${tmp[@]}")
	unset tmp
fi
versions=( "${versions[@]%/}" )

# Parameters: version, variant
function build () {
	workdir="$PWD"
	dockertag="$1"
	dockerdir="$1"
	if [ -n "$2" ]; then dockertag="$dockertag-$(echo $2 | tr '/' '-')"; dockerdir="$dockerdir/$2"; fi

	echo "Building $dockertag"
	cd "$dockerdir"
	echo $(date --utc --iso-8601=seconds) > build.log
	time docker build --rm --tag greencape/php:$dockertag . >> build.log
	echo $(date --utc --iso-8601=seconds) >> build.log
	cd "$workdir"
}

for version in "${versions[@]}"; do
	rcVersion="${version%-rc}"
	build "$version"

	if [ -d "$version/alpine" ]; then
		build "$version" "alpine"
	fi

	for target in \
		apache \
		fpm fpm/alpine \
		zts zts/alpine \
	; do
		[ -d "$version/$target" ] || continue
		build "$version" "$target"
	done
done
