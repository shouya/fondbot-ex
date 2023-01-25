#!/bin/bash

podman build . -t git.lain.li/shouya/fondbot:latest
podman push git.lain.li/shouya/fondbot:latest
