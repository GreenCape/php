#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

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

generated_warning() {
	cat <<-EOH
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

	EOH
}

# Make version number comparable
vc() { echo "$@" | awk -F. '{ printf("%03d%03d%03d\n", $1,$2,$3); }'; }

travisEnv=
for version in "${versions[@]}"; do
	rcVersion="${version%-rc}"

	fullVersion=`vendor/bin/php-versions version "$rcVersion"`
	basename=`vendor/bin/php-versions download-url "$rcVersion" --format xz`
	url=`vendor/bin/php-versions download-url "$rcVersion" --format xz --url`
	ascUrl=`vendor/bin/php-versions download-url "$rcVersion" --format xz --asc --url`
	sha256=`vendor/bin/php-versions hash "$rcVersion" --format xz --type sha256`
	md5=`vendor/bin/php-versions hash "$rcVersion" --format xz --type md5`

	gpgKey=`vendor/bin/php-versions gpg "$rcVersion"`
	if [ -z "$gpgKey" ]; then
		gpgKey='""'
	fi

	# if we don't have a .asc URL, let's see if we can figure one out :)
	if [ -z "$ascUrl" ] && wget -q --spider "$url.asc"; then
		ascUrl="$url.asc"
	fi

	# Temporarily disable GPG check due to problems with keyserver response time
	ascUrl=

	dockerfiles=()

	{ generated_warning; cat Dockerfile-debian.template; } > "$version/Dockerfile"
	cp -v \
		docker-php-entrypoint \
		docker-php-ext-* \
		docker-php-source \
		"$version/"
	if [ $(vc $version) -lt $(vc 5.3) ]; then
		cp -v libxml29_compat.patch "$version/"
	fi
	dockerfiles+=( "$version/Dockerfile" )

	if [ -d "$version/alpine" ]; then
		{ generated_warning; cat Dockerfile-alpine.template; } > "$version/alpine/Dockerfile"
		cp -v \
			docker-php-entrypoint \
			docker-php-ext-* \
			docker-php-source \
			"$version/alpine/"
		if [ $(vc $version) -lt $(vc 5.3) ]; then
			cp -v libxml29_compat.patch "$version/alpine/"
		fi
		dockerfiles+=( "$version/alpine/Dockerfile" )
	fi

	for target in \
		apache \
		fpm fpm/alpine \
		zts zts/alpine \
	; do
		[ -d "$version/$target" ] || continue
		base="$version/Dockerfile"
		variant="${target%%/*}"
		if [ "$target" != "$variant" ]; then
			variantVariant="${target#$variant/}"
			[ -d "$version/$variantVariant" ] || continue
			base="$version/$variantVariant/Dockerfile"
		fi
		echo "Generating $version/$target/Dockerfile from $base + $variant-Dockerfile-block-*"
		awk '
			$1 == "##</autogenerated>##" { ia = 0 }
			!ia { print }
			$1 == "##<autogenerated>##" { ia = 1; ab++; ac = 0 }
			ia { ac++ }
			ia && ac == 1 { system("cat '$variant'-Dockerfile-block-" ab) }
		' "$base" > "$version/$target/Dockerfile"
		cp -v \
			docker-php-entrypoint \
			docker-php-ext-* \
			docker-php-source \
			"$version/$target/"
		if [ $(vc $version) -lt $(vc 5.3) ]; then
			cp -v libxml29_compat.patch "$version/$target/"
		fi
		if [ "$target" == "apache" ]; then
			cp -v apache2-foreground "$version/$target/"
		fi
		dockerfiles+=( "$version/$target/Dockerfile" )
	done

	(
		set -x
		sed -ri \
			-e 's!%%PHP_VERSION%%!'"$fullVersion"'!' \
			-e 's!%%GPG_KEYS%%!'"$gpgKey"'!' \
			-e 's!%%PHP_FILE%%!'"$basename"'!' \
			-e 's!%%PHP_URL%%!'"$url"'!' \
			-e 's!%%PHP_ASC_URL%%!'"$ascUrl"'!' \
			-e 's!%%PHP_SHA256%%!'"$sha256"'!' \
			-e 's!%%PHP_MD5%%!'"$md5"'!' \
			"${dockerfiles[@]}"
	)

	# update entrypoint commands
	for dockerfile in "${dockerfiles[@]}"; do
		cmd="$(awk '$1 == "CMD" { $1 = ""; print }' "$dockerfile" | tail -1 | jq --raw-output '.[0]')"
		entrypoint="$(dirname "$dockerfile")/docker-php-entrypoint"
		sed -i 's! php ! '"$cmd"' !g' "$entrypoint"
	done

	newTravisEnv=
	for dockerfile in "${dockerfiles[@]}"; do
		dir="${dockerfile%Dockerfile}"
		dir="${dir%/}"
		variant="${dir#$version}"
		variant="${variant#/}"
		newTravisEnv+='\n  - VERSION='"$version VARIANT=$variant"
	done
	travisEnv="$newTravisEnv$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
