#!/usr/bin/env bash

set -e

cleanup() {
    rm /tmp/test.pcap
    rm /tmp/fifo
}

trap cleanup EXIT

echo Started some simple termshark tests.

echo Installing termshark for test use.

go install ./...

echo Making a test pcap.

cat <<EOF | xxd -r -p > /tmp/test.pcap
d4c3b2a102000400
0000000000000000
0000040006000000
f32a395200000000
4d0000004d000000
1040002035012b59
0006291793f8aaaa
0300000008004500
0037f93900004011
a6dbc0a82c7bc0a8
2cd5f93900450023
8d730001433a5c49
424d54435049505c
6c63636d2e31006f
6374657400f32a39
52000000004d0000
004d000000104000
2035012b59000629
1793f8aaaa030000
00080045000037f9
3900004011a6dbc0
a82c7bc0a82cd5f9
39004500238d7300
01433a5c49424d54
435049505c6c6363
6d2e31006f637465
7400
EOF

echo Running termshark cli tests.

# if timeout is invoked because termshark is stuck, the exit code will be non-zero
export TS="$GOPATH/bin/termshark"

# stdout is not a tty, so falls back to tshark
$TS -r /tmp/test.pcap | grep '192.168.44.213 TFTP 77'

# prove that options provided are passed through to tshark 
[[ $($TS -r /tmp/test.pcap -T psml -n | grep '<packet>' | wc -l) == 2 ]]

# Must choose either a file or an interface
! $TS -r /tmp/test.pcap -i eth0

# only display the second line via tshark
[[ $($TS -r /tmp/test.pcap 'frame.number == 2' | wc -l) == 1 ]]

# test fifos
mkfifo /tmp/fifo
cat /tmp/test.pcap > /tmp/fifo &
$TS -r /tmp/fifo | grep '192.168.44.213 TFTP 77'
wait
rm /tmp/fifo

# Check pass-thru option works. Make termshark run in a tty to ensure it's taking effect
[[ $(script -q -e -c "$TS -r /tmp/test.pcap --pass-thru" | wc -l) == 2 ]]

[[ $(script -q -e -c "$TS -r /tmp/test.pcap --pass-thru=true" | wc -l) == 2 ]]

# run in script so termshark thinks it's in a tty
cat version.go | grep -o -E "v[0-9]+\.[0-9]+(\.[0-9]+)?" | \
    xargs -i bash -c "script -q -e -c \"$TS -v\" | grep {}"

echo Running termshark UI tests.

in_tty() {
    ARGS=$@    # make into one token
    socat - EXEC:"bash -c \\\"stty rows 50 cols 80 && TERM=xterm && $ARGS\\\"",pty,setsid,ctty 
}

echo UI test 1
# Load a pcap, quit
{ sleep 5s ; echo q ; echo ; } | in_tty $TS -r /tmp/test.pcap

echo UI test 2
# Run with stdout not a tty, but disable the pass-thru to tshark
{ sleep 5s ; echo q ; echo ; } | in_tty "$TS -r /tmp/test.pcap --pass-thru=false | cat"

echo UI test 3
# Load a pcap, very rudimentary scrape for an IP, quit
{ sleep 5s ; echo q ; echo ; } | in_tty "$TS -r /tmp/test.pcap" | grep -a 192.168.44.123 > /dev/null

# Ensure -r flag isn't needed
{ sleep 5s ; echo q ; echo ; } | in_tty "$TS /tmp/test.pcap" | grep -a 192.168.44.123 > /dev/null

echo UI test 4
# Load a pcap from stdin
{ sleep 5s ; echo q ; echo ; } | in_tty "cat /tmp/test.pcap | TERM=xterm $TS -i -"
{ sleep 5s ; echo q ; echo ; } | in_tty "cat /tmp/test.pcap | TERM=xterm $TS -r -"
{ sleep 5s ; echo q ; echo ; } | in_tty "cat /tmp/test.pcap | TERM=xterm $TS"

echo UI test 5
# Display filter at end of command line
{ sleep 5s ; echo q ; echo ; } | in_tty "$TS -r scripts/pcaps/telnet-cooked.pcap \'frame.number == 2\'" | grep -a "Frame 2: 74 bytes" > /dev/null

echo UI test 6
mkfifo /tmp/fifo
cat /tmp/test.pcap > /tmp/fifo &
{ sleep 5s ; echo q ; echo ; } | in_tty "$TS -r /tmp/fifo"
wait
cat /tmp/test.pcap > /tmp/fifo &
{ sleep 5s ; echo q ; echo ; } | in_tty "$TS -i /tmp/fifo"
wait
cat /tmp/test.pcap > /tmp/fifo &
{ sleep 5s ; echo q ; echo ; } | in_tty "$TS /tmp/fifo"
#{ sleep 5s ; echo q ; echo ; } | in_tty "$TS /tmp/fifo \'frame.number == 2\'" | grep -a "Frame 2: 74 bytes" > /dev/null
wait

echo Tests were successful.
