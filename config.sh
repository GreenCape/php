#!/usr/bin/env bash

source ~/official-images/test/config.sh

testAlias+=(
	["greencape/php"]='php'
	["greencape/php:apache"]='php:apache'
	["greencape/php:fpm"]='php:fpm'
)
