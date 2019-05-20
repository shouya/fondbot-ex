#!/bin/bash

mix deps.get
mix compile

MIX_ENV=prod mix release

