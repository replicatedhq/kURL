# vendorflights

The purpose of this program is to take a kurl installer spec, parse the host preflights defined (if any) and write those preflights to a file. The file should only be written if there is a valid troubleshoot spec inside of the cluster installer spec.

##  Usage

vendorflights -i INPUT_FILE -o OUTPUT_FILE

INPUT_FILE: The filepath to a kurl installer spec .yaml file
OUTPUT_FILE: The filepath where the hostPreflight yaml file will be written (if defined in the spec)
