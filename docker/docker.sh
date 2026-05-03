#!/bin/bash

exec udocker run --nobanner --env=TZ=Asia/Ho_Chi_Minh --volume="$PWD":/workdir --workdir=/workdir --volume="$HOME"/.ssh:/root/.ssh docker-cli docker "$@"

