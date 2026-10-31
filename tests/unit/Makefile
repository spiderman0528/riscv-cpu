# Unit tests: cocotb + Icarus Verilog (pip install cocotb pytest)
PYTHON ?= python3

test:
	$(PYTHON) -m pytest -q test_units.py

clean:
	rm -rf sim_build results.xml __pycache__ .pytest_cache

.PHONY: test clean
