# Oracle-Linux-SEGV
Debugging instability

**Update**
There were two SEGV Issues.
- First was caused by a defect in the DBD::Oracle module (has been corrected by pull request(s) containing new tests and defect corrected)
- Second was caused by a defect in Perl signal handling where non-Perl threads entered Perl to service an interrupt. I hear that one fix was offered int "blead", another has been incorporated into 5.40.2; each having a differnt approach but testing seems to be stable and the SEGV no longer rears its ugly head

