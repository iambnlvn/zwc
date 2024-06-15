# Project Name

**ZWC**

## Description

ZWC is a zig implementation of the `wc` command. It counts the number of lines, words, and characters in a file.

## Installation

To install this project, follow these steps:

1. Clone the repository.<br>
   **2.1 Manually via:**

```sh
git clone https://github.com/iambnlvn/zwc
```

**2.2 Using gh cli:**

```sh
gh repo clone iambnlvn/zwc
```

2. Build the project with `zig build`.
3. Run the project with `./zig-out/bin/zwc`.

## Usage

To use `zwc`,

```sh
./zig-out/bin/zwc <file>
```

`zwc` supports standard input, so you can also use it like this:

```sh
echo "Say hi to your mom" | ./zig-out/bin/zwc
```

`
zwc supports the following flags:

- `-l`: Print the number of lines in the file.
- `-w`: Print the number of words in the file.
- `-c`: Print the number of characters in the file.
- `-m`: is the default flag, and it prints the number of lines, words, and characters in the file.

<br>
