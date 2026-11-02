 
%python
%pip install openpyxl
 
 %python
%restart_python

%python

import pandas as pd
source="/Volumes/retail/bronze/landing/online_retail_II.xlsx"
sheets=["Year 2009-2010","Year 2010-2011"]
for sheet in sheets:
  df = pd.read_excel(source, sheet_name=sheet, dtype=str)
  target=f"/Volumes/retail/bronze/landing/online_retail_{sheet[-9:].replace("-", "_")}.csv"
  df.to_csv(target, index=False)
  print(f"{sheet}: {len(df):,} rows written to {target}")




