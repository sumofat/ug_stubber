package main 
import fmt "core:fmt"
import utf8 "core:unicode/utf8"

TokenType :: enum{
	Identifier,
    Paren,
    OpenParen,
    CloseParen,
    Asterisk,
    OpenBrace,
    CloseBrace,
    LessThanSign,
    GreaterThanSign,
    String,
    SemiColon,
    Colon,
    Period,
    Dash,
    Underscore,
    Comma,
    EndOfStream,
    Comment,
    Pound,
    ReturnCarriage,
    NewLine,
	ForwardSlash,
	BackwardSlash,
    Pipe,
    Unknown,
}

Token :: struct{
	type : TokenType,
	data : string,
}

Tokenizer :: struct{
	src : string,
	offset : int,
	last_token : ^Token,
	at : rune,
}

is_whitespace :: proc(r : rune) -> bool{
	if r == ' '  ||
       r == '\t' ||
       r == '\n' ||
       r == '\r'{
       	return true
    }
    return false
}
is_alpha :: proc(r : rune)-> bool{
	result : bool = ((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z'))
    return result
}

is_num :: proc(r : rune) -> bool{
    return (r >= '0' && r <= '9') || (r == '-') || (r == '.')
}

is_allowed_in_identifier :: proc(r : rune)-> bool{
    return (r == '_');
}
is_whitespace_no_end_of_line :: proc(r : rune) -> bool{
	if r == ' '  ||
       r == '\t'{
       	return true
    }
    return false
}

is_comment_start :: proc(token : Token,other : Token) -> bool{
    return (token.type == .ForwardSlash && other.type == .Asterisk);
}

is_comment_end :: proc(token : Token,other : Token) -> bool{
    return (token.type == .Asterisk && other.type == .ForwardSlash);
}

current_rune :: proc(tokenizer : Tokenizer) -> (rune,int){
	return utf8.decode_rune_in_string(tokenizer.src[tokenizer.offset:])
}

advance :: proc(tokenizer : ^Tokenizer,by : int){
	tokenizer.offset += by
	w : int
	tokenizer.at,w = current_rune(tokenizer^)
}

advance_by_current :: proc(tokenizer : ^Tokenizer) -> rune{
	r, w := utf8.decode_rune_in_string(tokenizer.src[tokenizer.offset:])
	tokenizer.offset += w
	next_r,next_w := current_rune(tokenizer^)
	tokenizer.at = next_r
	return tokenizer.at
}

eat_all_whitespace :: proc(tokenizer : ^Tokenizer, is_included_end_of_line_chars : bool){
	if is_included_end_of_line_chars{
		r := tokenizer.at
		for is_whitespace(r){
			r = advance_by_current(tokenizer)
		}
	}else{
		temp_offset := tokenizer.offset
		r := tokenizer.at
		for is_whitespace_no_end_of_line(r){
			r = advance_by_current(tokenizer)
		}
	}
}

get_token :: proc(tokenizer : ^Tokenizer) -> Token{
	result : Token
	eat_all_whitespace(tokenizer,true)
	r,width := current_rune(tokenizer^)
	for !is_whitespace(r){
		switch r{
			case ';':{result.type = .SemiColon;advance(tokenizer,width);return result;}
			case '(':{result.type = .OpenBrace;advance(tokenizer,width);return result;}
			case ')':{result.type = .CloseBrace;advance(tokenizer,width);return result;}
			case '{':{result.type = .OpenParen;advance(tokenizer,width);return result;}
			case '}':{result.type = .CloseParen;advance(tokenizer,width);return result;}
			case ':':{result.type = .Colon;advance(tokenizer,width);return result;}
			case ',':{result.type = .Comma;advance(tokenizer,width);return result;}
			case '.':{result.type = .Period;advance(tokenizer,width);return result;}
			case '-':{result.type = .Dash;advance(tokenizer,width);return result;}
			case '#':{result.type = .Pound;advance(tokenizer,width);return result;}
			case '<':{result.type = .LessThanSign;advance(tokenizer,width);return result;}
			case '>':{result.type = .GreaterThanSign;advance(tokenizer,width);return result;}
			case '/':{result.type = .ForwardSlash;advance(tokenizer,width);return result;}
			case '\\':{result.type = .BackwardSlash;advance(tokenizer,width);return result;}
			case '*':{result.type = .Asterisk;advance(tokenizer,width);return result;}
			//case '\0':{result.type = .Pipe;advance(tokenizer,width);return result;}
			case '"':{
				result.type = .String
				r = advance_by_current(tokenizer)
				for r != '"'{
					r = advance_by_current(tokenizer)
				}
				result.data = tokenizer.src[tokenizer.offset:]				
				return result
			}
			default :{
				result.type = .Identifier
				r = advance_by_current(tokenizer)
				for is_alpha(r) || is_num(r) || is_allowed_in_identifier(r){
					r = advance_by_current(tokenizer)					
				}
				result.data = tokenizer.src[tokenizer.offset:]
				return result
			}
		}
	}

	return result
}

GLHeaderDataBlockType :: enum{
    glheader_data_func_sig,
    glheader_data_func_impl,
    glheader_data_func_other,
}

GLHeaderDataBlock :: struct{
    type : GLHeaderDataBlockType,
    tokens : [dynamic]Token,
}

GLHeaderData :: struct{
    header_data_block : [dynamic]GLHeaderDataBlock,
}

parse_gl_header :: proc(input : string){
	result : GLHeaderData
	result.header_data_block  = make([dynamic]GLHeaderDataBlock) 
	tokenizer_ : Tokenizer
	tokenizer := &tokenizer_
	tokenizer.src = input
	w : int
	tokenizer.at,w = current_rune(tokenizer^)
	tokens : [dynamic]Token = make([dynamic]Token)
	prev_token : Token

	is_parsing : bool
	is_function : bool

	for is_parsing{
		token := get_token(tokenizer)
		append(&tokens,token)

		if is_comment_start(prev_token,token){
			max_iterations_allowed := max(int)
			for i := 0;i < max_iterations_allowed;i += i{
				token = get_token(tokenizer)
				if is_comment_end(prev_token,token){
					break
				}
				prev_token = token
			}
			continue
		}

		if token.type == .Identifier{
			if token.data == "GL_API" && prev_token.data == "define"{
				block : GLHeaderDataBlock
				block.type = .glheader_data_func_sig
                block.tokens = make([dynamic]Token)
                //beggining of function definition.
                is_function = true;
                append(&block.tokens,token)
                for{
                	token = get_token(token)
                	append(&block.tokens,token)
                	is_function = false
					if token.type != .SemiColon{
						break
					}
					prev_token = token
                }
                append(&result.header_data_block,block)
			}
		}
	}

}


main ::  proc(){
	using fmt
	println("UG STUBBER INIT")


	test := "    hello string world"
	tt : Tokenizer
	tt.src = test

	println(tt.src[tt.offset:])

	a,w := current_rune(tt)
	println(a,w)
	newr := advance_by_current(&tt)
	a,w = current_rune(tt)
	println(a,w)

	println(tt.at)


	eat_all_whitespace(&tt,true)

	println(tt.src[tt.offset:])

	input_gl_h := string(#load("headers_to_stub/gl.h"))
	input_gl_ext_h := string(#load("headers_to_stub/glext.h"))
	
	
	


}