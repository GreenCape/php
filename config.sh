#!/usr/bin/env bash

source ~/official-images/test/config.sh

testAlias+=(
	["greencape/php:7.0"]='php'
	["greencape/php:7.0-alpine"]='php'
	["greencape/php:7.0-apache"]='php:apache'
	["greencape/php:7.0-fpm"]='php:fpm'
	["greencape/php:7.0-fpm-alpine"]='php:fpm'
	["greencape/php:7.0-zts"]='php'
	["greencape/php:7.0-zts-alpine"]='php'
)
