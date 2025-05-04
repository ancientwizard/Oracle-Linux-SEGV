# Oracle-Linux-SEGV
Debugging instability

**Update**
The instability was false (concerning instantclient). It was caused by a mistake on my part and Copilot helping.
The DBD::Oracle 1.90 implementation does have and issue and causes the last OCISessionEnd to SEGV.
The conditions are:
- Three+ threads all connect to the same DB/account etc (this is what I did, perhaps other combos also)
- Then after all threee are connected the last one to disconnect will SEGV.

