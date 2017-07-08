#!/bin/bash
echo 'workaround builder'

touch Makefile
echo -e 'COMPONENT=BlinkAppC\ninclude $(MAKERULES)' > Makefile

make telosb

cp --remove-destination --recursive build ../

rm -rf build

rm Makefile
