#!/usr/bin/env bash

# pyvenv.sh - Manage Python virtual environments

set -e

# 1. Safety Check: Ensure the variable is set
if [ -z "$PYTHON_VDIR" ]; then
    echo "Error: \$PYTHON_VDIR is not set."
    echo "Please add 'export PYTHON_VDIR=\"$HOME/.python_venvs\"' to your config."
    exit 1
fi

# 2. Ensure the directory actually exists
if [ ! -d "$PYTHON_VDIR" ]; then
    mkdir -p "$PYTHON_VDIR"
fi

cmd="$1"
name="$2"
venv_path="$PYTHON_VDIR/$name"

case "$cmd" in
    create)
        if [ -z "$name" ]; then
            echo "Usage: pyvenv.sh create <env_name>"
            exit 1
        else
            echo "Creating venv in $venv_path..."
            python -m venv "$venv_path"
        fi
        ;;

    activate)
        if [ -f "$venv_path/bin/activate" ]; then
            # shellcheck disable=SC1090
            source "$venv_path/bin/activate"
        elif [ -f "$venv_path/Scripts/activate" ]; then
            # shellcheck disable=SC1090
            source "$venv_path/Scripts/activate"
        else
            echo "Error: venv '$name' not found in $PYTHON_VDIR"
            exit 1
        fi
        ;;

    list)
        ls -1 "$PYTHON_VDIR"
        ;;

    remove|rm|delete)
        if [ -z "$name" ]; then
            echo "Usage: pyvenv.sh remove <env_name>"
            exit 1
        fi

        if [ ! -d "$venv_path" ]; then
            echo "Error: venv '$name' not found in $PYTHON_VDIR"
            exit 1
        fi

        read -r -p "Are you sure you want to delete '$name'? [y/N] " confirm
        case "$confirm" in
            y|Y|yes|YES)
                echo "Removing $venv_path..."
                rm -rf "$venv_path"
                ;;
            *)
                echo "Aborted."
                ;;
        esac
        ;;

    *)
        echo "Usage: pyvenv.sh {create|activate|list|remove} <name>"
        exit 1
        ;;
esac
