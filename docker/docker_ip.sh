#!/bin/bash

docker inspect -f '{{range $name, $net := .NetworkSettings.Networks}}{{printf "%s: %s\n" $name $net.IPAddress}}{{end}}' "$@"
