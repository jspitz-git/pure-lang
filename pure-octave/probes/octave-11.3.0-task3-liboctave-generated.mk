# Generate the prerequisites omitted by Octave 11.3.0's direct liboctave
# target.  Keep this tied to the upstream variables instead of duplicating
# Octave's generated-header inventory here.
.PHONY: task3-liboctave-generated
task3-liboctave-generated: $(BUILT_INCS) octave-config.h liboctave/version.h
