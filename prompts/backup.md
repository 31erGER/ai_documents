Backup task (safety-critical, verify before deleting anything):

    SOURCE: /run/media/julian/FRANZ_2  (14.5 GiB USB stick)
    TARGET: /run/media/julian/1TB_JULIAN  (1 TB disk, ~500 GB free)
                                                                                                                                                                             ·
    Goal: ensure every file on the stick exists on the 1 TB disk, then delete the                                                                                            ·
    verified files from the stick.                                                                                                                                           ·
                                                                                                                                                                             ▸
    Protocol (follow exactly, no shortcuts):
 1. Use absolute paths in every command. Never rely on the working directory.
 2. Enumerate all files on the stick: find + sizes. Check filenames contain no
    tabs/newlines; check NUL-count == line-count.
 3. Identify where this stick's data belongs on the disk. Previous stick's data
    (Bausatz VPS Aufgaben, Gefangenen Assets, Julian Franz, Praxis Übungen,
    Schlosser, Theorie - Infos+Unterrichtsmaterial, VDE-Bestimmungen) was backed
    up under "/run/media/julian/1TB_JULIAN/Backup Anstalt/Schulserver/". If the
    new stick's top-level folders match that pattern, use that mapping;
    otherwise search the 1 TB disk for matching relative paths and show me the
    mapping before proceeding.
 4. Match EVERY file one by one by name + size (join/comm, LC_ALL=C).                                                                                                       ▸
    Classify: SAME (name+size match) / SIZE_MISMATCH / MISSING.                                                                                                             ·
    Report counts. If any SIZE_MISMATCH: do NOT delete those files, show the                                                                                                ·
    list and stop to ask me.                                                                                                                                                ·
 5. Aggregate check: sum of all matched file sizes on stick == sum on disk.                                                                                                 ·
 6. Content spot-check: SHA-256 compare a sample (~100 random + 10 largest +
    10 smallest). Any mismatch => stop and report.
 7. Copy only MISSING files into the mapped location (preserve paths).
    Verify each copied file by size + SHA-256 before it counts as backed up.
 8. Only after everything is verified: delete from the stick exactly the listed
    verified paths (xargs -d '\n' rm -- < list, no wildcards, no -r).
    Deleting ~18k small files on USB takes ~10-15 min and may exceed your
    command timeout: run it in the background (setsid nohup ... &) and poll
    the remaining file count until done; resume from a fresh "remaining" list
    if a timeout interrupts it (all remaining files are still verified).
 9. Skip "System Volume Information" (Windows metadata) by default; mention it
    in the final report. Do not remove empty directories without my approval.
 10. Final report: counts matched/copied/deleted, bytes totals, remaining
     files on stick, disk file count before/after (must only grow by the
     number of copied files).

    Authorization: files verified to exist on the 1 TB disk (name+size+checksum
    per protocol) are pre-approved for deletion from the stick. Nothing else may
    be deleted or modified. Never use rm -r / rm -rf.
