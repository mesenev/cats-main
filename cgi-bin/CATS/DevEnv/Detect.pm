package CATS::DevEnv::Detect;

# Guesses the development environment of a submission from its text, for the
# "Auto" choice on the submit form. Plain rules, no external service: each
# language family scores points for constructs typical of it, and the best
# family wins only if it is clearly ahead. A submission that is only links
# (e.g. a GitHub repository) is text. Families map to DE codes in order of
# preference, and only DEs the problem allows are considered.

use strict;
use warnings;

use Encode ();

# Family => DE codes, most preferred first. Look-alike variants (PyPy, Clang
# with sanitizers, PascalABC) and legacy DOS/Windows compilers (Borland, MS
# Visual C++, QBasic) are never picked automatically: they stay explicit choices.
our %family_des = (
    text    => [ 3, 1 ],
    cpp     => [ 102, 106 ],
    c       => [ 105, 102 ],   # C compiles as C++ where only C++ is allowed
    python  => [ 502, 510 ],
    java    => [ 401 ],
    csharp  => [ 407, 402 ],
    unity   => [ 602 ],
    js      => [ 507 ],
    go      => [ 404 ],
    rust    => [ 120 ],
    nasm    => [ 130 ],
    pascal  => [ 202, 204 ],
    delphi  => [ 204, 202 ],
    basic   => [ 302 ],
    kotlin  => [ 406 ],
    perl    => [ 501 ],
    haskell => [ 503 ],
    ruby    => [ 504 ],
    php     => [ 505 ],
    erlang  => [ 506 ],
    prolog  => [ 509 ],
    r       => [ 511 ],
    # SQLite (520); older SQL problems take SQL as Python (502) through the
    # std.sql.main module.
    sql     => [ 520, 502 ],
    tex     => [ 606 ],
    xml     => [ 5 ],
);

# [ family, points, regex ]; each rule scores once per submission.
my @rules = (
    [ cpp => 5, qr/^\s*#\s*include\s*<(?:iostream|vector|string|algorithm|map|set|unordered_map|queue|stack|fstream|sstream|iomanip|cmath|cstdio|cstdlib|cstring|bits\/stdc\+\+\.h)>/m ],
    [ cpp => 5, qr/\busing\s+namespace\s+std\b/ ],
    [ cpp => 4, qr/\bstd::/ ],
    [ cpp => 4, qr/\b(?:cout|cerr)\s*<<|\bcin\s*>>/ ],
    [ cpp => 3, qr/\btemplate\s*</ ],
    [ cpp => 3, qr/\bnullptr\b|\bvector\s*</ ],
    [ c => 3, qr/^\s*#\s*include\s*<(?:stdio|stdlib|string|math|ctype|stdbool|limits|stdint)\.h>/m ],
    [ c => 2, qr/\bprintf\s*\(/ ],
    [ c => 2, qr/\bscanf\s*\(/ ],
    [ c => 2, qr/\bmalloc\s*\(/ ],
    [ c => 2, qr/\bint\s+main\s*\(/ ],
    [ c => 2, qr/"[^"\n]*%(?:l{0,2}[dfiu]|s|c|lf)[^"\n]*"/ ],
    [ python => 4, qr/^\s*def\s+\w+\s*\(.*\)\s*(?:->\s*[^:]+)?:\s*(?:#.*)?$/m ],
    [ python => 4, qr/^\s*from\s+[\w.]+\s+import\s+/m ],
    [ python => 2, qr/^\s*import\s+[\w.]+(?:\s+as\s+\w+)?(?:\s*,\s*[\w.]+)*\s*$/m ],
    [ python => 3, qr/\binput\s*\(\s*\)/ ],
    [ python => 2, qr/\bprint\s*\(/ ],
    [ python => 2, qr/^print\s*\(/m ],
    [ python => 3, qr/\bsys\.(?:stdin|stdout|argv|setrecursionlimit)\b/ ],
    [ python => 2, qr/\bmap\s*\(\s*int\b|\.split\s*\(\s*\)|\.strip\s*\(\s*\)/ ],
    [ python => 2, qr/^\s*(?:if|elif|else|for|while|try|except|with|class)\b[^;{]*:\s*(?:#.*)?$/m ],
    [ python => 2, qr/\brange\s*\(|\blen\s*\(|\bNone\b/ ],
    [ python => 3, qr/__name__\s*==|\bself\.\w|\bf"|\bf'|\belif\b/ ],
    [ java => 8, qr/\bpublic\s+static\s+void\s+main\s*\(\s*(?:final\s+)?String/ ],
    [ java => 6, qr/\bSystem\.out\.print/ ],
    [ java => 6, qr/^\s*import\s+java\./m ],
    [ java => 2, qr/\bnew\s+Scanner\s*\(\s*System\.in/ ],
    [ csharp => 6, qr/^\s*using\s+System\b/m ],
    [ csharp => 6, qr/\bConsole\.(?:Write|Read)/ ],
    [ csharp => 4, qr/\bstatic\s+(?:async\s+)?(?:void|int|Task)\s+Main\s*\(/ ],
    [ js => 5, qr/\bconsole\.log\s*\(/ ],
    [ js => 5, qr/\bprocess\.stdin\b|\brequire\s*\(\s*['"](?:readline|fs)['"]\s*\)/ ],
    [ js => 2, qr/^\s*(?:let|const|var)\s+\w+\s*=/m ],
    [ js => 2, qr/\bfunction\s+\w*\s*\(|=>\s*[{(]/ ],
    [ go => 8, qr/^\s*package\s+main\b/m ],
    [ go => 6, qr/\bfunc\s+main\s*\(\s*\)/ ],
    [ go => 5, qr/\bfmt\.(?:Print|Scan|Sprint|Fprint)/ ],
    [ pascal => 6, qr/^\s*program\s+\w+\s*;/mi ],
    [ pascal => 5, qr/\bend\s*\.\s*\z/i ],
    [ pascal => 3, qr/\bbegin\b/i ],
    [ pascal => 4, qr/\b(?:writeln|readln)\b/i ],
    [ pascal => 2, qr/^\s*var\b/mi ],
    [ pascal => 2, qr/^\s*uses\s+\w/mi ],
    [ delphi => 6, qr/\{\$APPTYPE\s+CONSOLE\}/i ],
    [ delphi => 3, qr/\buses\b[^;]*\bSysUtils\b/i ],
    [ perl => 6, qr/^\s*use\s+(?:strict|warnings)\s*;/m ],
    [ perl => 4, qr/\bmy\s+[\$\@%]\w/ ],
    [ perl => 2, qr/\$_\b|<STDIN>|\bchomp\b/ ],
    [ rust => 8, qr/\bfn\s+main\s*\(\s*\)/ ],
    [ rust => 6, qr/\b(?:println|print|eprintln|vec|format)!\s*[(\[]/ ],
    [ rust => 5, qr/\blet\s+mut\s+\w/ ],
    [ rust => 5, qr/^\s*use\s+std::\w+(?:::\{|::\w|;)/m ],
    [ rust => 2, qr/&mut\s|\bimpl\b|->\s*(?:i32|i64|u32|u64|usize|String|bool)\b/ ],
    [ nasm => 8, qr/^\s*section\s+\.(?:text|data|bss)\b/mi ],
    [ nasm => 6, qr/^\s*global\s+(?:_start|main)\b/mi ],
    [ nasm => 4, qr/^\s*(?:mov|push|pop|call|ret|xor|syscall)\b/mi ],
    [ basic => 6, qr/^\s*Dim\s+\w+(?:\s*\([^)]*\))?\s+As\s+\w/mi ],
    [ basic => 3, qr/^\s*End\s+(?:If|Sub|Function|Select)\b/mi ],
    [ basic => 3, qr/^\s*Next\b/mi ],
    [ basic => 2, qr/^\s*(?:Print|Input)\b(?!\s*\()/mi ],
    [ kotlin => 8, qr/\bfun\s+main\s*\(/ ],
    [ kotlin => 4, qr/\breadln(?:OrNull)?\s*\(\)|\breadLine\s*\(\)\s*!!/ ],
    [ kotlin => 3, qr/^\s*val\s+\w+(?:\s*:\s*\w+)?\s*=/m ],
    [ haskell => 8, qr/^main\s*(?:::|=)/m ],
    [ haskell => 6, qr/^import\s+(?:qualified\s+)?Data\./m ],
    [ haskell => 4, qr/\b(?:putStrLn|getLine|interact|getContents)\b/ ],
    [ haskell => 3, qr/::\s*(?:IO|Int|Integer|String|\[)/ ],
    [ ruby => 3, qr/\bputs\b(?!\s*\()/ ],
    [ ruby => 3, qr/\bgets\b(?!\s*\()/ ],
    [ ruby => 5, qr/\.each(?:_with_index)?\s+do\s*\||\.map\s*\(&:\w+\)|\.split\.map\b/ ],
    [ ruby => 3, qr/#\{\w/ ],
    [ ruby => 2, qr/^\s*end\s*$/m ],
    [ php => 10, qr/<\?php/ ],
    [ php => 4, qr/\bfgets\s*\(\s*STDIN\s*\)|\bfscanf\s*\(\s*STDIN\b/ ],
    [ php => 2, qr/\becho\b/ ],
    [ erlang => 10, qr/^-module\(/m ],
    [ erlang => 6, qr/^-export\(/m ],
    [ erlang => 6, qr/\bio:(?:format|fread|get_line)\(/ ],
    [ prolog => 8, qr/:-\s*initialization\b/ ],
    [ prolog => 6, qr/^[a-z]\w*(?:\([^)]*\))?\s*:-/m ],
    [ prolog => 2, qr/\b(?:write|writeln|nl|read_term)\b/ ],
    [ r => 6, qr/\breadLines\s*\(|\bscan\s*\(\s*(?:file\s*=\s*)?["'](?:stdin|stdin)["']/ ],
    [ r => 5, qr/\blibrary\s*\(\s*\w+\s*\)/ ],
    [ r => 3, qr/^\s*\w+\s*<-\s*(?:c|function|as\.\w+|readLines|scan)\b/m ],
    [ r => 3, qr/\bcat\s*\(/ ],
    [ tex => 10, qr/\\documentclass\b/ ],
    [ tex => 6, qr/\\begin\{document\}/ ],
    [ xml => 10, qr/\A\s*<\?xml\b/ ],
    [ unity => 10, qr/^\s*using\s+UnityEngine\b/m ],
    [ sql => 4, qr/\bSELECT\b[\s\S]+?\bFROM\b/i ],
    [ sql => 4, qr/\A\s*(?:SELECT|WITH|PRAGMA)\b/i ],
    [ sql => 4, qr/\b(?:CREATE\s+TABLE|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM)\b/i ],
    [ sql => 2, qr/\b(?:WHERE|GROUP\s+BY|ORDER\s+BY|JOIN)\b/i ],
);

my $min_score = 4;

sub _decode {
    my ($text) = @_;
    return $text if utf8::is_utf8($text);
    my $copy = $text;
    eval { Encode::decode('UTF-8', $copy, Encode::FB_CROAK) } // undef;
}

# Returns a hashref { family => 'cpp', scores => {...} } or { family => undef, reason => '...' }.
sub family {
    my ($text) = @_;
    defined $text && $text ne '' or return { reason => 'empty' };
    $text =~ /\x00/ and return { reason => 'binary' };
    my $t = _decode($text) // return { reason => 'binary' };

    my @lines = grep /\S/, split /\r?\n/, $t;
    return { family => 'text', reason => 'links' }
        if @lines && @lines == grep m{^\s*<?(?:https?://|www\.)\S+>?\s*$}i, @lines;

    my %scores;
    for (@rules) {
        my ($f, $points, $rx) = @$_;
        $scores{$f} += $points if $t =~ $rx;
    }
    # Delphi is Pascal with extras: one family, the markers only pick the DE.
    if ($scores{delphi}) {
        $scores{delphi} += delete $scores{pascal} // 0;
    }
    # Unity scripts are C# with UnityEngine; Rust's `use std::` is not C++.
    delete $scores{csharp} if ($scores{unity} // 0) >= 10;
    delete $scores{cpp} if ($scores{rust} // 0) >= 8;
    # C++ code usually contains C constructs too.
    delete $scores{c} if ($scores{cpp} // 0) >= $min_score;
    # SQL is often embedded in other code as strings (sqlite problems):
    # it counts only when no programming language is recognized.
    delete $scores{sql} if grep { $_ ne 'sql' && $scores{$_} >= $min_score } keys %scores;

    my ($best, $second) = sort { $scores{$b} <=> $scores{$a} || $a cmp $b } grep $scores{$_}, keys %scores;
    if (!$best || $scores{$best} < $min_score) {
        # Not code, but a link with a few words around it is still an answer text.
        return { family => 'text', reason => 'short text with a link' }
            if @lines <= 3 && length($t) <= 500 && $t =~ m{https?://|\b(?:github|gitlab)\.com/}i;
        return { reason => 'no code recognized', scores => \%scores };
    }
    my $s2 = $second ? $scores{$second} : 0;
    $scores{$best} >= 2 * $s2 || $scores{$best} - $s2 >= 6
        or return { reason => "ambiguous: $best or $second", scores => \%scores };
    { family => $best, scores => \%scores };
}

# $allowed: arrayref of allowed DE codes. Returns ($de_code, $info).
sub de_code {
    my ($text, $allowed) = @_;
    my %ok = map { $_ => 1 } @$allowed;
    my $r = family($text);
    $r->{family} or return (undef, $r);
    my ($code) = grep $ok{$_}, @{$family_des{$r->{family}} // []};
    defined $code or return (undef, { %$r, reason => "$r->{family} is not allowed here" });
    ($code, $r);
}

1;
