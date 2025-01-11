;--------------------------------------------------------------;
PRINT_STRING MACRO s
	mov ah, 09h
	lea dx, s
	int 21h
ENDM
;--------------------------------------------------------------;


model small
.stack 100h
.data

welcome_message db 'Welcome to turbo cool tokenizer!', 13, 10, '$'
tokenize_prompt db "What do you want me to tokenize (input a filename): $"
show_tokens_prompt db "Would you like me to show some of the most common tokens? (y/N) $"
select_prompt db "How many tokens do you want me to show? $"
show_tokens_message db "Here are the most common tokens:", 13, 10, '$'
here_are_your_tokens db "Here are your tokens:", 13, 10, '$'
extracted_message db "Extracted $"
tokens_message db " tokens.", 13, 10, '$'
success_message db "Tokens written to TOKENS.TXT.", 13, 10, '$'
file_error_message db "File operation failiure.", 13, 10, '$'
invalid_number_message db "Invalid number.", 13, 10, '$'
new_line db 10, '$'

input_file db 13, 0, 13 dup(0)
output_file db "TOKENS.TXT", 0

token_buffer_len dw 0
token_buffer db 3010 dup(' ')

token_count_1 dw 0

token_pointers_1 dw 1010 dup(?)
counts_1 dw 1010 dup(?)

token_count_2 dw 0
token_pointers_2 dw 1010 dup(0)
counts_2 dw 3010 dup(0)

fd dw 2

tmp db 10 dup(?)

.code

;--------------------------------------------------------------;
start:
	mov	ax, @data
	mov	ds, ax

	PRINT_STRING welcome_message
	PRINT_STRING tokenize_prompt

	mov ah, 0ah
	lea dx, input_file
	int 21h
	xor bx, bx
	mov bl, input_file[1]
	add bl, 2
	mov input_file[bx], 0

	PRINT_STRING new_line

	call init_token_buffer
	call init_token_pointers_1

	PRINT_STRING extracted_message
	mov ax, token_count_1
	lea si, tmp
	call itoa
	mov bx, cx
	mov tmp[bx], '$'

	PRINT_STRING tmp
	PRINT_STRING tokens_message

	call create_token_multiset
	call selection_sort

	xor ax, ax
	call format_output_buffer

	lea dx, output_file
	call create_file
	mov bx, 0fffh
	call write_tokenized_output
	call close_fd

	PRINT_STRING success_message

	mov ax, 1
	call format_output_buffer

__output_N_tokens:
	PRINT_STRING show_tokens_prompt

	mov ah, 01h
	int 21h
	cmp al, 'y'
	jne exit

	PRINT_STRING new_line
	PRINT_STRING select_prompt

	mov tmp, 4
	mov tmp[1], 0
	mov ah, 0ah
	lea dx, tmp
	int 21h

	PRINT_STRING new_line

	xor cx, cx
	mov cl, tmp[1]
	mov bx, 2

check_valid_number:
	mov al, tmp[bx]
	cmp al, '0'
	jl invalid_number_error
	cmp al, '9'
	jg invalid_number_error
	inc bx
	loop check_valid_number

	PRINT_STRING here_are_your_tokens

	lea si, tmp[2]
	mov cl, tmp[1]
	call atoi

	mov fd, 1 ; write to stdout
	mov bx, ax
	call write_tokenized_output

exit:
	mov	ax,4c00h
	int	21h

invalid_number_error:
	PRINT_STRING invalid_number_message
	jmp __output_N_tokens
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Reads the contents of input_file into a temporary buffer (token_pointers_1),
; applies a token-stream transformation to the buffer,
; and writes the transformed output to token_buffer.
;
; (Raw input -> Token-stream) transformation:
; Each uppercase letter is converted to a lowercase letter.
; Whitespace is inserted before and after each of the characters "!", "?", ".".
; All other characters except "'" are converted to whitespace.
init_token_buffer proc
	lea dx, input_file[2]
	call open_file

	; This is fucked up. We use token_pointers_1 buffer for storing the raw input.
	mov cx, 1000
	lea dx, token_pointers_1
	call read_from_fd

	push ax
	call close_fd
	pop cx

	xor si, si
	xor di, di

__init_token_buffer_copy_loop:
	mov al, byte ptr token_pointers_1[si]
	cmp al, 'z'
	jg __init_token_buffer_to_whitespace
	cmp al, 'a'
	jge __init_token_buffer_copy_character
	cmp al, 'Z'
	jg __init_token_buffer_to_whitespace
	cmp al, 'A'
	jge __init_token_buffer_to_lowercase
	cmp al, '!'
	je __init_token_buffer_punctuation_character
	cmp al, '?'
	je __init_token_buffer_punctuation_character
	cmp al, '.'
	je __init_token_buffer_punctuation_character
	cmp al, 39 ; "'"
	je __init_token_buffer_copy_character

	jmp __init_token_buffer_to_whitespace

__init_token_buffer_to_lowercase:
	add al, 32 ; 32 = 'A' - 'a'
	jmp __init_token_buffer_copy_character

__init_token_buffer_punctuation_character:
	mov token_buffer[di], ' '
	inc di
	mov token_buffer[di], al
	inc di
	mov token_buffer[di], ' '
	inc di
	jmp __init_token_buffer_loop_inc

__init_token_buffer_to_whitespace:
	mov al, ' '
__init_token_buffer_copy_character:
	mov token_buffer[di], al
	inc di

__init_token_buffer_loop_inc:
	inc si
	loop __init_token_buffer_copy_loop

	mov token_buffer_len, di
	ret
init_token_buffer endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Fills the token_pointers_1 array with pointers to tokens in token_buffer,
; sets token_count_1 to the number of tokens in token_buffer.
init_token_pointers_1 proc
	xor si, si
	xor bx, bx ; holds token count * 2

__init_token_pointers_1_loop:
	cmp si, token_buffer_len
	jge __init_token_pointers_1_exit

	cmp token_buffer[si], ' '
	je __init_token_pointers_1_loop_inc
	cmp si, 0
	je __init_token_pointers_1_new_token
	cmp token_buffer[si-1], ' '
	jne __init_token_pointers_1_loop_inc

__init_token_pointers_1_new_token:
	lea ax, token_buffer[si]
	mov token_pointers_1[bx], ax
	add bx, 2 ; 2 because words are 2 bytes

__init_token_pointers_1_loop_inc:
	inc si
	jmp __init_token_pointers_1_loop

__init_token_pointers_1_exit:
	shr bx, 1
	mov token_count_1, bx
	ret
init_token_pointers_1 endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Fills token_pointers_2 with pointers to unique tokens in token_buffer.
; Sets token_count_2 to the number of unique tokens in token_buffer.
; Fills the counts_2 array with the number of occurences for each token.
;
; Note: Assumes token_pointers_1 is initialized.
create_token_multiset proc
	xor cx, cx
__create_token_multiset_loop:
	cmp cx, token_count_1
	jge __create_token_multiset_exit

	mov bx, cx
	add bx, cx ; bx = 2 * cx
	mov bx, token_pointers_1[bx]
	call add_token_to_token_multiset

	inc cx
	jmp __create_token_multiset_loop
__create_token_multiset_exit:
	ret
create_token_multiset endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Adds the token referenced by bx to the token multiset.
;
; This is a subprocedure of create_token_multiset.
;
; Contaminates:
; ax, bx, dx, si, di
add_token_to_token_multiset proc
	xor dx, dx
__add_token_to_token_multiset_loop:
	cmp dx, token_count_2
	jge __add_token_to_token_multiset_create_new_token

	mov si, dx
	add si, dx ; si = dx * 2
	mov si, token_pointers_2[si]
	mov di, bx

	push bx
	call strcmp
	pop bx
	cmp ax, 0 ; token is already in multiset
	je __add_token_to_token_multiset_inc_token_count
	inc dx
	jmp __add_token_to_token_multiset_loop

__add_token_to_token_multiset_create_new_token:
	mov si, dx
	add si, dx ; si = dx * 2
	mov token_pointers_2[si], bx
	mov counts_2[si], 0

	mov ax, token_count_2
	inc ax
	mov token_count_2, ax

__add_token_to_token_multiset_inc_token_count:
	mov si, dx
	add si, dx ; si = dx * 2
	inc counts_2[si]
	ret
add_token_to_token_multiset endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Sorts the token multiset stored in token_pointers_2 and counts_2.
; The sorted result is written out-of-place to token_pointers_1 and counts_1.
selection_sort proc
	xor di, di
	mov ax, token_count_2
	mov token_count_1, ax

__selection_sort_loop:
	cmp di, token_count_2
	jge __selection_sort_exit
	call find_min

	shl si, 1
	shl di, 1
	mov ax, token_pointers_2[si]
	mov token_pointers_1[di], ax
	mov ax, counts_2[si]
	mov counts_1[di], ax
	mov counts_2[si], 2025h
	shr di, 1

	inc di
	jmp __selection_sort_loop

__selection_sort_exit:
	ret
selection_sort endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Finds the index of the rarest token in the token multiset stored in token_pointers_2 and counts_2
;
; Return register: si
;
; Contaminates:
; ax, bx, si
find_min proc
	; bx = iterating index
	; si = candidate index
	xor bx, bx
	xor si, si

__find_min_loop:
	cmp bx, token_count_2
	jge __find_min_exit

	shl bx, 1
	shl si, 1
	mov ax, counts_2[bx]
	cmp counts_2[si], ax
	jle __find_min_inc
	mov si, bx
__find_min_inc:
	shr bx, 1
	shr si, 1
	inc bx
	jmp __find_min_loop
__find_min_exit:
	ret
find_min endp
;--------------------------------------------------------------;



;--------------------------------------------------------------;
; Formats the token multiset stored in token_pointers_1 and counts_1 into the counts_2 buffer.
; Fills token_pointers_2 with pointers to formatted token entries.
;
; Arguments:
; ax - 0 if the tokens should be formatted in ascending order.
format_output_buffer proc
	xor bx, bx
	lea di, counts_2
	push ax
__format_output_buffer_loop:
	cmp bx, token_count_1
	jge __format_output_buffer_loop_out

	pop ax
	push ax

	push bx

	cmp ax, 0
	je __format_output_buffer_ascending
__format_output_buffer_descending:
	; otherwise convert to descending index
	; si = token_count_1 - 1 - bx
	mov si, token_count_1
	dec si
	sub si, bx
	jmp __format_output_buffer_continue

__format_output_buffer_ascending:
	mov si, bx

__format_output_buffer_continue:
	shl si, 1
	push si
	shl bx, 1 ; index scaling
	mov si, token_pointers_1[si]
	mov token_pointers_2[bx], di

	call strcpy

	pop si

	mov byte ptr [di], ' '
	inc di

	mov ax, counts_1[si]
	lea si, tmp
	call itoa
	lea si, tmp
	add si, cx
	mov byte ptr [si], ' '

	lea si, tmp
	call strcpy

	mov byte ptr [di], 13 ; \r
	inc di
	mov byte ptr [di], 10 ; \n
	inc di

	pop bx
	inc bx
	jmp __format_output_buffer_loop
__format_output_buffer_loop_out:
	pop ax
	shl bx, 1
	mov token_pointers_2[bx], di; sentinel
	ret
format_output_buffer endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Writes min(bx, token_count_2) entries from
; the tokenized output (stored in counts_2) to file descriptor fd.
write_tokenized_output proc
	cmp bx, token_count_2
	jle __write_tokenized_output_branch
	mov bx, token_count_2

__write_tokenized_output_branch:
	lea dx, counts_2
	shl bx, 1 ; index scaling
	mov cx, token_pointers_2[bx]
	shr bx, 1
	lea ax, counts_2
	sub cx, ax
	call write_to_fd
	ret
write_tokenized_output endp
;--------------------------------------------------------------;


;**************************************************************;
;                     STRING OPERATIONS                        ;
;**************************************************************;


;--------------------------------------------------------------;
; Compares whitespace (' ') terminated strings referenced in si and di.
; Returns (in ax):
;  0 if *si = *di
;  1 if *si > *di
; -1 if *si < *di
; Assumes that si and di point to valid whitespace-terminated strings.
;
; Contaminates:
; ax, bx, si, di
strcmp proc
__strcmp_loop:
	mov al, [si]
	mov bl, [di]
	cmp al, bl
	jg __strcmp_res_greater
	jl __strcmp_res_less

	cmp al, ' '
	je __strcmp_res_eq

	inc si
	inc di
	jmp __strcmp_loop

__strcmp_res_greater:
	mov ax, 1
	ret
__strcmp_res_less:
	mov ax, -1
	ret
__strcmp_res_eq:
	xor ax, ax
	ret
strcmp endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Copies a ' '-separated string to a new location.
; Advances di to the end of the new string.
;
; Arguments:
; si - a pointer to the source string
; di - a pointer to the destination string
;
;
; Contaminates:
; ax, si, di
strcpy proc
__strcpy_loop:
	mov al, byte ptr [si]
	cmp al, ' '
	je __strcpy_loop_out
	mov byte ptr [di], al
	inc si
	inc di
	jmp __strcpy_loop
__strcpy_loop_out:
	ret
strcpy endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Returns the length of a ' '-separated string.
;
; Arguments:
; si - a pointer to the string
;
; Return register - ax
;
; Contaminates:
; ax, si
strlen proc
	mov ax, si
__strlen_loop:
	cmp byte ptr [si], ' '
	je __strlen_loop_out
	inc si
	jmp __strlen_loop
__strlen_loop_out:
	sub si, ax
	mov ax, si
	ret
strlen endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Converts a string to an unsigned integer.
;
; This function is really primitive.
; It's assumed that the string is a valid number.
;
; Arguments:
; si - string pointer
; cx - string length
;
; Return register: ax
;
; Contaminates:
; ax, bx, cx, dx, si
atoi proc
	xor ax, ax
	xor dx, dx
	mov bx, 10
__atoi_loop:
	mul bx
	mov dl, byte ptr [si]
	add ax, dx
	sub ax, '0'
	inc si
	loop __atoi_loop
	ret
atoi endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Converts an unsigned integer to string.
; Arguments:
; ax - integer to convert
; si - pointer to destination buffer
;
; Return registers:
; cx - number of digits
;
; Contaminates:
; ax, bx, cx, dx
itoa proc
	push ax
	mov bx, 10
	call count_digits
	pop ax
	push cx
	add si, cx
itoa_loop:
	dec si
	xor dx, dx
	div bx ; ax = ax / bx ; dx = ax % bx
	add dx, '0'
	mov byte ptr [si], dl
	loop itoa_loop

	pop cx
	ret
itoa endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Counts the number of digits of an unsigned integer.
; Arguments:
; ax - the integer
; bx - base
;
; Return values:
; cx - number of digits
;
; Contaminates:
; ax, cx, dx
count_digits proc
	mov cx, 1
__count_digits_loop:
	xor dx, dx
	div bx ; ax = ax / bx ; dx = ax % bx
	cmp ax, 0
	je __count_digits_loop_out
	inc cx
	jmp __count_digits_loop

__count_digits_loop_out:
	ret
count_digits endp
;--------------------------------------------------------------;


;**************************************************************;
;                      FILE OPERATIONS                         ;
;**************************************************************;


;--------------------------------------------------------------;
; Creates a file and saves its file descriptor in the fd variable.
; It's assumed that a pointer to a 0-terminated filename is passed to dx.
create_file proc
	; create output file
	mov ah, 3ch
	xor cx, cx ; normal attributes
	int 21h
	jc __create_file_error
	mov fd, ax
	ret
__create_file_error:
	PRINT_STRING file_error_message
	jmp near ptr exit
create_file endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Opens a file and save its file descriptor in the fd variable.
; It's assumed that a pointer to a 0-terminated filename is passed to dx.
open_file proc
	mov ah, 3dh
	mov al, 00h
	int 21h
	jc __open_file_error
	mov fd, ax
	ret
__open_file_error:
	PRINT_STRING file_error_message
	jmp near ptr exit
open_file endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Reads up to cx bytes from file descriptor fd into a dx-referenced buffer.
; Returns the bytes read into ax.
read_from_fd proc
	mov ah, 3fh
	mov bx, fd
	int 21h
	jc __read_from_fd_error
	ret
__read_from_fd_error:
	PRINT_STRING file_error_message
	jmp near ptr exit
read_from_fd endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Writes cx bytes from dx-referenced buffer to file descriptor fd.
write_to_fd proc
	mov ah, 40h
	mov bx, fd
	int 21h
	jc __write_to_fd_error
	ret
__write_to_fd_error:
	PRINT_STRING file_error_message
	jmp near ptr exit
write_to_fd endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Deletes a file.
; It's assumed that a pointer to a 0-terminated filename is passed to dx.
delete_file proc
	mov ah, 41h
	int 21h
	jc __delete_file_error
	ret
__delete_file_error:
	PRINT_STRING file_error_message
	jmp near ptr exit
delete_file endp
;--------------------------------------------------------------;


;--------------------------------------------------------------;
; Closes the file descriptor stored in the fd variable.
close_fd proc
	mov ah, 3eh
	mov bx, fd
	int 21h
	jc __close_fd_error
	ret
__close_fd_error:
	PRINT_STRING file_error_message
	jmp near ptr exit
close_fd endp
;--------------------------------------------------------------;


end start
