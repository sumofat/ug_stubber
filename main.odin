package main 
import fmt "core:fmt"
import utf8 "core:unicode/utf8"
import strings "core:strings"

GLStubifyReturnTypes :: enum{
    gl_returntype_void,
    gl_returntype_uint,
    gl_returntype_int,
    gl_returntype_glbool,
    gl_returntype_gluint,
    gl_returntype_glubyte,
    gl_returntype_glenum,
    gl_returntype_nullpointer,
    gl_returntype_glsync,//is a pointer to a struct
}

GLReturnType :: struct{
    flags : u32,
    token : Token,
    is_pointer : bool,
}

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

parse_gl_header :: proc(input : string) -> GLHeaderData{
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
                	token = get_token(tokenizer)
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
	return result
}


GetReturnString :: proc(type : GLStubifyReturnTypes)-> string
{
    result : string
    switch(type)
    {
        case .gl_returntype_void:{
            result = "\treturn;\n"
        }
        case .gl_returntype_uint:{
            result = "\treturn 0;\n"
        }
        case .gl_returntype_int:{
            result = "\treturn 0;\n"
        }
        case .gl_returntype_glbool:{
            result = "\treturn false;\n"
        }
        case .gl_returntype_glubyte:{
            result = "\treturn 0;\n"
        }
        case .gl_returntype_gluint:{
            result = "\treturn 0;\n"
        }
        case .gl_returntype_glenum:{
            result = "\treturn 0;\n"
        }
        case .gl_returntype_nullpointer:{
            result = "\treturn 0;\n"
        }
        case .gl_returntype_glsync:{
            result = "\treturn 0;\n"
        }
        default:{
        	assert(false)
        }
    }
    return result;
}

main ::  proc(){
	using fmt
	using strings
	println("UG STUBBER INIT")

/*
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
*/




	input_gl_h := string(#load("headers_to_stub/gl.h"))
	input_gl_ext_h := string(#load("headers_to_stub/glext.h"))

	return_type_info : GLReturnType  = {};
	out_builder_ := make_builder_none()
	out_builder := &out_builder_

	header_data := parse_gl_header(input_gl_h)
	next_token : Token
	prev_token : Token
	for block , i  in header_data.header_data_block{
		for t, j in block.tokens{
			if j + 1 < len(header_data.header_data_block){
				next_token = block.tokens[(j+1)]
			}

			if t.type == .OpenParen{
				if prev_token.data == "OPENGLES_DEPRECATED"{
					open_paren_count := 0
					close_paren_count := 0
					k := j
					for {
						tt := block.tokens[k]
						if tt.type == .OpenParen{
							open_paren_count += 1
						}else if tt.type == .CloseParen{
							close_paren_count += 1
						}

						if open_paren_count != close_paren_count{
							k += 1
						}else{
							j = k
							break
						}
					}
					continue
				}

				//Todo(Ray):add to string output here
				write_rune_builder(out_builder,'(')

			}else if t.type == .CloseParen{
				//add string output
				write_rune_builder(out_builder,')')
			}else if t.type == .SemiColon{
				// NOTE(Ray Garner): This is the end of the signature
                //we throw away the semicolon and add create our braces
                //and return type here.
                //Yostr func_stub = CreateStringFromLiteral("\n{\n",&func_sig_temp_arena);
                //GLStubifyReturnTypes return_type = {};

                func_stub := "\n{\n"
				return_type : GLStubifyReturnTypes

                // NOTE(Ray Garner): If its a pointer typee we will always return a null pointer type is equivalent to zero.
                if return_type_info.is_pointer || "GLsync" == return_type_info.token.data{
                	return_type = .gl_returntype_void
                }else{
                	if "void" == return_type_info.token.data{
                		return_type = .gl_returntype_void
                	}else if "GLuint" == return_type_info.token.data{
                		return_type = .gl_returntype_gluint
                	}else if return_type_info.token.data == "int"{
                        return_type = .gl_returntype_int;
                    }else if return_type_info.token.data == "GLboolean"{
                        return_type = .gl_returntype_glbool;
                    }else if return_type_info.token.data == "GLenum"{
                        return_type = .gl_returntype_glenum;
                    }else if return_type_info.token.data == "GLubyte"{
                        return_type = .gl_returntype_glubyte;
                    }else if return_type_info.token.data == "GLenum"{
                        return_type = .gl_returntype_glenum;
                    }
                }
                return_statement : string// = AppendString(func_stub,GetReturnString(return_type,&func_sig_temp_arena),&func_sig_temp_arena);
                //func_stub = AppendString(return_statement,CreateStringFromLiteral("}\n\n",&func_sig_temp_arena),&func_sig_temp_arena);
				//AppendStringSameFrontArena(gl_h_output,func_stub,sm);
                //DeAllocatePartition(&func_sig_temp_arena,false);
                return_type_info.is_pointer = false; 
                return_type_info.flags = 0;
                                
			}
		}
	}


}