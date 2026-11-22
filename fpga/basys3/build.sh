#!/bin/bash
f4pga -vv build --flow presenter-basys3.json
mkdir -p build/log
mv *.log build/log/
cp build/basys3/fpga_top.bit presenter.bit
