#!/usr/bin/env python3
import ctypes
import os
import sys

SCMP_ACT_TRAP = 0x00030000
SCMP_ACT_ALLOW = 0x7FFF0000

ALLOWED = set('''
access arch_prctl brk capget chdir chmod clock_getres clock_gettime clock_nanosleep
clone clone3 close copy_file_range creat dup dup2 dup3 epoll_create epoll_create1
epoll_ctl epoll_pwait epoll_pwait2 epoll_wait eventfd eventfd2 execve execveat exit
exit_group faccessat faccessat2 fallocate fchmod fchmodat fcntl fdatasync fgetxattr
flistxattr flock fork fstat fstatfs fsync ftruncate futex futex_time64 futimesat
get_mempolicy getcwd getdents getdents64 getegid geteuid getgid getgroups getitimer
getpgid getpgrp getpid getppid getpriority getrandom getresgid getresuid getrlimit
getrusage getsid gettid gettimeofday getuid getxattr ioctl kill lseek lstat madvise
mbind membarrier memfd_create mincore mkdir mkdirat mlock mmap mprotect mremap msync munlock
munmap nanosleep newfstatat nice open openat openat2 pipe pipe2 poll ppoll prctl
pread64 preadv preadv2 prlimit64 pselect6 pwrite64 pwritev pwritev2 read readlink
readlinkat readv recvfrom recvmsg rename renameat renameat2 rmdir rseq rt_sigaction
rt_sigpending rt_sigprocmask rt_sigqueueinfo rt_sigreturn rt_sigsuspend rt_sigtimedwait
sched_get_priority_max sched_get_priority_min sched_getaffinity sched_getparam
sched_getscheduler sched_setaffinity sched_setscheduler sched_yield select sendfile
sendmsg sendto set_robust_list set_tid_address setitimer setpgid setpriority setrlimit
setsid sigaltstack socketpair splice stat statfs statx sync_file_range sysinfo tee
tgkill time timer_create timer_delete timer_getoverrun timer_gettime timer_settime
timerfd_create timerfd_gettime timerfd_settime times tkill umask uname unlink unlinkat
utime utimensat utimes vfork vmsplice wait4 waitid waitpid write writev
'''.split())


def main():
    if len(sys.argv) != 2:
        raise SystemExit(f'Usage: {sys.argv[0]} OUTPUT.bpf')
    lib = ctypes.CDLL('libseccomp.so.2')
    lib.seccomp_init.argtypes = [ctypes.c_uint32]
    lib.seccomp_init.restype = ctypes.c_void_p
    lib.seccomp_syscall_resolve_name.argtypes = [ctypes.c_char_p]
    lib.seccomp_syscall_resolve_name.restype = ctypes.c_int
    lib.seccomp_rule_add.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int, ctypes.c_uint]
    lib.seccomp_rule_add.restype = ctypes.c_int
    lib.seccomp_export_bpf.argtypes = [ctypes.c_void_p, ctypes.c_int]
    lib.seccomp_export_bpf.restype = ctypes.c_int
    lib.seccomp_release.argtypes = [ctypes.c_void_p]

    ctx = lib.seccomp_init(SCMP_ACT_TRAP)
    if not ctx:
        raise MemoryError('seccomp_init failed')
    try:
        for name in sorted(ALLOWED):
            nr = lib.seccomp_syscall_resolve_name(name.encode())
            if nr < 0:
                continue
            rc = lib.seccomp_rule_add(ctx, SCMP_ACT_ALLOW, nr, 0)
            if rc:
                raise OSError(f'seccomp_rule_add failed for {name}: {rc}')
        fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
        try:
            if lib.seccomp_export_bpf(ctx, fd):
                raise OSError('seccomp_export_bpf failed')
        finally:
            os.close(fd)
    finally:
        lib.seccomp_release(ctx)


if __name__ == '__main__':
    main()
