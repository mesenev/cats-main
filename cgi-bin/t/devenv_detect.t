use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

use lib File::Spec->catdir($FindBin::Bin, '..');

use CATS::DevEnv::Detect;

my @all = (1, 3, 5, 102, 105, 106, 107, 120, 130, 202, 204, 302, 401, 402, 404, 406, 407,
    501, 502, 503, 504, 505, 506, 507, 509, 510, 511, 520, 602, 606);

sub detects {
    my ($expected, $src, $name, $allowed) = @_;
    my ($code, $info) = CATS::DevEnv::Detect::de_code($src, $allowed // \@all);
    is $code, $expected, $name or diag explain $info;
}

# One small program per language.
my @programs = (
    [ 102, 'C++', <<'SRC' ],
#include <iostream>
using namespace std;
int main() { int a, b; cin >> a >> b; cout << a + b << endl; }
SRC
    [ 105, 'C', <<'SRC' ],
#include <stdio.h>
int main(void) { int a, b; scanf("%d %d", &a, &b); printf("%d\n", a + b); return 0; }
SRC
    [ 502, 'Python', "a, b = map(int, input().split())\nprint(a + b)\n" ],
    [ 401, 'Java', <<'SRC' ],
import java.util.Scanner;
public class Main {
    public static void main(String[] args) {
        Scanner in = new Scanner(System.in);
        System.out.println(in.nextInt() + in.nextInt());
    }
}
SRC
    [ 407, 'C#', <<'SRC' ],
using System;
class Program {
    static void Main() {
        var p = Console.ReadLine().Split();
        Console.WriteLine(int.Parse(p[0]) + int.Parse(p[1]));
    }
}
SRC
    [ 507, 'JavaScript', <<'SRC' ],
const lines = require('fs').readFileSync(0, 'utf8').trim().split(' ');
console.log(Number(lines[0]) + Number(lines[1]));
SRC
    [ 404, 'Go', <<'SRC' ],
package main

import "fmt"

func main() {
	var a, b int
	fmt.Scan(&a, &b)
	fmt.Println(a + b)
}
SRC
    [ 120, 'Rust', <<'SRC' ],
use std::io;
fn main() {
    let mut s = String::new();
    io::stdin().read_line(&mut s).unwrap();
    let v: Vec<i64> = s.split_whitespace().map(|x| x.parse().unwrap()).collect();
    println!("{}", v[0] + v[1]);
}
SRC
    [ 130, 'Nasm', <<'SRC' ],
global _start
section .text
_start:
    mov rax, 60
    xor rdi, rdi
    syscall
SRC
    [ 202, 'Free Pascal', <<'SRC' ],
program sum;
var a, b: integer;
begin
    readln(a, b);
    writeln(a + b);
end.
SRC
    [ 204, 'Delphi mode', <<'SRC' ],
program sum;
{$APPTYPE CONSOLE}
uses SysUtils;
var a, b: Integer;
begin
    Readln(a, b);
    Writeln(a + b);
end.
SRC
    [ 302, 'Free Basic', <<'SRC' ],
Dim a As Integer
Dim b As Integer
Input a, b
Print a + b
SRC
    [ 406, 'Kotlin', <<'SRC' ],
fun main() {
    val (a, b) = readln().split(" ").map { it.toInt() }
    println(a + b)
}
SRC
    [ 501, 'Perl', <<'SRC' ],
use strict;
use warnings;
my ($a, $b) = split ' ', <STDIN>;
print $a + $b, "\n";
SRC
    [ 503, 'Haskell', <<'SRC' ],
main :: IO ()
main = interact $ show . sum . map read . words
SRC
    [ 504, 'Ruby', "a, b = gets.split.map(&:to_i)\nputs a + b\n" ],
    [ 505, 'PHP', <<'SRC' ],
<?php
fscanf(STDIN, "%d %d", $a, $b);
echo $a + $b, "\n";
SRC
    [ 506, 'Erlang', <<'SRC' ],
-module(main).
-export([main/0]).
main() -> {ok, [A, B]} = io:fread("", "~d ~d"), io:format("~w~n", [A + B]).
SRC
    [ 509, 'Prolog', <<'SRC' ],
:- initialization(main).
main :- read(A), read(B), C is A + B, write(C), nl, halt.
SRC
    [ 511, 'R', <<'SRC' ],
x <- scan(file("stdin"))
cat(sum(x), "\n")
SRC
    [ 520, 'SQLite', "SELECT name, COUNT(*) AS n\nFROM orders\nGROUP BY name\nORDER BY n DESC;\n" ],
    [ 602, 'Unity', "using UnityEngine;\npublic class Mover : MonoBehaviour {\n    void Update() { }\n}\n" ],
    [ 606, 'TeX', "\\documentclass{article}\n\\begin{document}\nHello\n\\end{document}\n" ],
    [ 5, 'XML', qq~<?xml version="1.0"?>\n<root><item/></root>\n~ ],
);
detects(@$_[0, 2, 1]) for @programs;

# The Hello, World! judge smoke-test solutions.
my $hello = File::Spec->catdir($FindBin::Bin, qw(.. .. tests judge-smoke hello-world sol));
for ([ 'hello.c', 105 ], [ 'hello.cc', 102 ], [ 'hello.pp', 202 ], [ 'hello.dpr', 204 ],
    [ 'hello.go', 404 ], [ 'hello.pl', 501 ], [ 'hello.py', 502 ], [ 'hello_pypy.py', 502 ]
) {
    my ($file, $code) = @$_;
    open my $f, '<', File::Spec->catfile($hello, $file) or die "$file: $!";
    detects($code, do { local $/; <$f> }, "hello world: $file");
}

# Cases seen in real submissions.
detects(3, "https://github.com/user/repo/commit/0123abcd\n", 'GitHub link is answer text');
detects(3, "Мессенджер https://github.com/user/chat.git\n", 'link with a word');
detects(3, "github.com/user/repo\n", 'link without a scheme');
detects(502, "print(\"no\")\n", 'Python one-liner');
detects(502, <<'SRC', 'SQL inside Python strings is Python');
import sqlite3
con = sqlite3.connect("a.db")
for row in con.execute("SELECT id, name FROM users WHERE age > 18 ORDER BY id"):
    print(row)
SRC
detects(520, "WITH RECURSIVE t AS (SELECT 1 AS n UNION ALL SELECT n + 1 FROM t WHERE n < 5)\nSELECT n FROM t;\n",
    'recursive SQL query');
detects(102, "#include <bits/stdc++.h>\nusing namespace std;\nint main() { printf(\"%d\", 1); }\n",
    'C++ with printf is still C++');
detects(105, "#include <stdio.h>\nint main() { char s[9]; gets(s); puts(s); }\n", 'C with puts/gets is not Ruby');
detects(undef, ".\n", 'a lone dot is ambiguous');
detects(undef, "1\n", 'a lone number is ambiguous');
detects(undef, "", 'empty');
detects(undef, "SQLite format 3\x00\x10\x00", 'binary (an SQLite database file)');

# Only allowed DEs are chosen.
detects(102, "#include <stdio.h>\nint main() { printf(\"%d\", 1); }\n", 'C as C++ where only C++ is allowed', [ 102 ]);
detects(502, "SELECT * FROM t;\n", 'SQL as Python where SQLite is not allowed', [ 502 ]);
detects(1, "https://github.com/user/repo\n", 'link as do-not-compile where answer text is not allowed', [ 1, 502 ]);
detects(510, "print(input())\n", 'PyPy where only PyPy is allowed', [ 510 ]);
detects(undef, "package main\nfunc main() {}\n", 'Go is refused where Go is not allowed', [ 102, 502 ]);
detects(406, "fun main() { println(readln()) }\n", 'Kotlin, not Java');

done_testing;
