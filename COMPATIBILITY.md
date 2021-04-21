# Compatibility Matrix

| Module version | Date released | PE min version | PE max version | CD4PE min version | CD4PE max version | ServiceNow min version | ServiceNow max version | Remarks |
| -------------- | ------------- | -------------- | -------------- | ----------------- | ----------------- | ---------------------- | --------------------- | ------- |
| 0.2.3 | 2021/04/09 | 2019.8.3 | 2021.1.0 | 3.13.4, 4.1.2 | 3.13.6, 4.5.0 | Orlando | Quebec | Slight bug in ServiceNow Quebec, where it creates 4 canceled change tasks upon completion of code promotion. When running a version less than 4.5.0 of CD4PE, an extra br_version parameter must be specified for the prep_servicenow plan (see README) |
| 0.2.2 | 2021/04/09 | 2019.8.3 | 2021.0.0 | 3.13.4, 4.1.2 | 3.13.6, 4.4.1 | Orlando | Quebec | Slight bug in ServiceNow Quebec, where it creates 4 canceled change tasks upon completion of code promotion |
| 0.2.1 | 2021/03/17 | 2019.8.3 | 2021.0.0 | 3.13.2, 4.0.1 | 3.13.5, 4.4.0 | Orlando | Quebec | Slight bug in ServiceNow Quebec, where it creates 4 canceled change tasks upon completion of code promotion |
| 0.2.0 | 2021/02/11 |2019.8.1 | 2019.8.4 | 3.12.3, 4.0.0 | 3.13.4, 4.3.2 | Orlando | Paris |  |
| 0.1.6 | 2020/11/17 |2019.7.0 | 2019.8.4 | 3.9.0, 4.0.0 | 3.13.4, 4.2.3 | New York | Paris |  |
| 0.1.5 | 2020/10/15 |2019.7.0 | 2019.8.1 | 3.8.0, 4.0.0 | 3.13.2, 4.1.3 | New York | Paris |  |
| 0.1.4 | 2020/09/25 |2019.7.0 | 2019.8.1 | 3.8.0, 4.0.0 | 3.13.2, 4.0.1 | New York | Paris |  |
| 0.1.3 | 2020/07/29 |2019.4.0 | 2019.8.0 | 3.8.0 | 3.12.2 | New York | Paris |  |
| 0.1.2 | 2020/07/13 |2019.4.0 | 2019.8.0 | 3.8.0 | 3.11.1 | New York | Paris |  |
| 0.1.1 | 2020/06/30 |2019.2.2 | 2019.8.0 | 3.8.0 | 3.11.1 | Madrid | Orlando |  |
| 0.1.0 | 2020/06/30 |2019.2.2 | 2019.8.0 | 3.8.0 | 3.11.1 | Madrid | Orlando |  |