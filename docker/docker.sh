#!/bin/bash

PROJECT_NAME=$(basename "$PWD")

exec udocker run --nobanner --env=COMPOSE_PROJECT_NAME="$PROJECT_NAME" --env=TZ=Asia/Ho_Chi_Minh --volume="$PWD":/workdir --workdir=/workdir --volume="$HOME"/.ssh:/root/.ssh docker-cli docker "$@"
