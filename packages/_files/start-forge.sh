#!/bin/sh
# Forge 1.17 and later: the installer writes the launch arguments to unix_args.txt.
# Before 1.17: the installer leaves a forge-*.jar to run.

UNIX_ARGS=$(echo libraries/net/minecraftforge/forge/*/unix_args.txt)

if [ -f "$UNIX_ARGS" ]; then
  java $JVM_ARGS @$UNIX_ARGS $SERVER_ARGS
else
  java $JVM_ARGS -jar forge-*.jar $SERVER_ARGS
fi
