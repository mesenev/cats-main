# testlib-style checker: check.py <input> <output> <answer>
# Exit codes: 0 = OK, 1 = Wrong Answer, 2 = Presentation Error.
import sys


def lines(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        result = [line.rstrip() for line in f.read().splitlines()]
    while result and not result[-1]:
        result.pop()
    return result


output, answer = lines(sys.argv[2]), lines(sys.argv[3])
if output == answer:
    print('ok')
    sys.exit(0)
if [l.strip().lower() for l in output if l.strip()] == [l.strip().lower() for l in answer]:
    print('presentation: expected %r, got %r' % (answer, output))
    sys.exit(2)
print('wrong answer: expected %r, got %r' % (answer, output[:3]))
sys.exit(1)
