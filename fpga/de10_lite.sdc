create_clock -name clk50 -period 20.000 [get_ports MAX10_CLK1_50]
create_generated_clock -name clk25 -source [get_ports MAX10_CLK1_50] -divide_by 2 [get_registers clk]
derive_clock_uncertainty
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to   [get_ports {LEDR[*] ARDUINO_IO[*]}]
