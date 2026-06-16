package com.jasperwizard;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;

/**
 * Runs the verified jasper-deploy scripts (PowerShell / Python) as child
 * processes and captures their combined output. Commands are always built as an
 * argument list -- never a shell string -- so user-supplied values (report names,
 * SQL) cannot break out into shell injection.
 */
public class ScriptRunner {

    public static class Result {
        public final int exit;
        public final String output;   // stdout + stderr, interleaved
        public final boolean timedOut;
        Result(int exit, String output, boolean timedOut) {
            this.exit = exit; this.output = output; this.timedOut = timedOut;
        }
        public boolean ok() { return !timedOut && exit == 0; }
    }

    private final File workingDir;
    private final int timeoutSec;
    private final Map<String, String> extraEnv;

    public ScriptRunner(File workingDir, int timeoutSec, Map<String, String> extraEnv) {
        this.workingDir = workingDir;
        this.timeoutSec = timeoutSec;
        this.extraEnv = extraEnv;
    }

    /** Invoke a PowerShell .ps1 with the given -Param value pairs already in args. */
    public Result powershell(String scriptPath, List<String> args) {
        List<String> cmd = new ArrayList<>();
        cmd.add("powershell.exe");
        cmd.add("-NoProfile");
        cmd.add("-NonInteractive");
        cmd.add("-ExecutionPolicy");
        cmd.add("Bypass");
        cmd.add("-File");
        cmd.add(scriptPath);
        cmd.addAll(args);
        return run(cmd);
    }

    /** Invoke a Python script with the given args. */
    public Result python(String pythonExe, String scriptPath, List<String> args) {
        List<String> cmd = new ArrayList<>();
        cmd.add(pythonExe);
        cmd.add(scriptPath);
        cmd.addAll(args);
        return run(cmd);
    }

    private Result run(List<String> cmd) {
        ProcessBuilder pb = new ProcessBuilder(cmd);
        if (workingDir != null) pb.directory(workingDir);
        pb.redirectErrorStream(true);
        if (extraEnv != null) pb.environment().putAll(extraEnv);
        try {
            Process p = pb.start();
            ByteArrayOutputStream buf = new ByteArrayOutputStream();
            // Drain output on a worker thread so a chatty process can't deadlock
            // by filling the pipe while we wait.
            Thread drain = new Thread(() -> {
                try (InputStream in = p.getInputStream()) {
                    byte[] b = new byte[4096];
                    int n;
                    while ((n = in.read(b)) != -1) buf.write(b, 0, n);
                } catch (Exception ignore) {}
            });
            drain.start();
            boolean done = p.waitFor(timeoutSec, TimeUnit.SECONDS);
            if (!done) {
                p.destroyForcibly();
                drain.join(2000);
                return new Result(-1, buf.toString("UTF-8") + "\n[TIMEOUT after " + timeoutSec + "s]", true);
            }
            drain.join(5000);
            return new Result(p.exitValue(), buf.toString("UTF-8"), false);
        } catch (Exception e) {
            return new Result(-1, "exec failed: " + e.getMessage(), false);
        }
    }
}
