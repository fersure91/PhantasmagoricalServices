#!/bin/bash

for X in `pgrep services.pl`; do
	if [[ `vdir /proc/$X/cwd |sed 's/.*-> //'` == `pwd` ]]; then
		kill $X
	fi
done
