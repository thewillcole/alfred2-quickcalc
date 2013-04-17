require 'shellwords'

class QuickCalc
  # Adds commas as a thousands separator
  # TODO: Support other locales
  def format_number(num)
    num_parts = num.to_s.split('.')
    formatted_number = num_parts.first.reverse.gsub(/...(?=.)/,'\&,').reverse
    formatted_number += '.' + num_parts[1] if num_parts.length > 1
    formatted_number
  end

  # Basically just converts a float to an int if it ends in .0
  # ...I'm bad at naming things.
  def remove_trailing_zero(float)
    if float - float.to_i == 0
      float.to_i
    else
      float
    end
  end

  def initialize(query, functions_file, custom_file)
    @query = query.dup
    @number_pattern = /([0-9]*\.[0-9]+|[0-9]+)/

    custom = File.open(custom_file) {|f| f.read }
    defaults = File.open(functions_file) {|f| f.read}

    balance_parentheses
    @query.strip!
    remove_trailing_operators

    @query = custom + "\n" + @query

    convert_thousands_suffixes
    replace_variables
    of_to_mult
    x_to_mult
    remove_superfluous_characters
    convert_percents

    @query.gsub!('π', 'pi')
    @query.gsub!('**', '^')

    @query = defaults + "\n" + @query
  end

  def calculate
    `echo #{Shellwords.escape(@query)} | bc -l 2>&1`.strip
  end

  def functions
    @functions || (@functions = find_functions(@query))
  end

  def variables
    @variables || (@variables = find_variables(@query))
  end

  # Auto-closes parentheses so we can get immediate results.
  # If we find a closing paren, but we can't find any unmatched open parens, add
  # an open paren to the beginning of the expression (either the beginning of
  # the query, or after the last semicolon (bc doesn't like variable definitions
  # being wrapped in parens)). Once we're done, add any necessary closing parens
  # to the end.
  def balance_parentheses
    num_open = 0
    num_closed = 0
    query_start = (@query.rindex(';') || -1) + 1

    @query.each_char do |char|
      if char == '('
        num_open += 1
      elsif char == ')'
        num_closed += 1
        if num_closed > num_open
          @query.insert(query_start, '(')
          num_open += 1
        end
      end
    end

    if num_open > num_closed
      @query << ')' * (num_open - num_closed)
    end
  end

  # Prevents it from showing 0 immediately after typing a new operator
  def remove_trailing_operators
    operators = %w[+ - / * ^ (]

    last_char = @query[@query.length - 1, 1]

    # Check if it ends with an operator (including 'x' for multiplication)
    # Make sure 'x' is an operator, and not just part of a variable name
    if operators.include?(last_char) || (@query =~ /([^a-z_]+[0-9]*)x$/) != nil
      @query.chop!
      remove_trailing_operators
    end
  end

  def remove_superfluous_characters
    # Remove spaces between numbers
    @query.gsub!(/(\d+)[\t ]+(\d+)/, '\1\2')
    # Removes commas that aren't followed by a space. If you want to separate
    # function arguments, press space after the comma.
    @query.gsub!(/,(?! )/, '')
    # Remove some common currency signs
    @query.gsub!('$', '')
    @query.gsub!('£', '')
    @query.gsub!('€', '')
    # Remove underscores after a number so they can be used as a thousands
    # separator, but still work in variable/function names.
    @query.gsub!(/(\d)_/, '\1')
  end

  def convert_thousands_suffixes
    @query.gsub!(/(#{@number_pattern})(k|m|b| thousand| million| billion)/) do |match|
      if $3 == 'k' || $3 == ' thousand'
        "#{$2}*1000"
      elsif $3 == 'm' || $3 == ' million'
        "#{$2}*1000000"
      elsif $3 == 'b' || $3 == ' billion'
        "#{$2}*1000000000"
      end
    end
  end

  # Make 'of' an alias of '*'
  def of_to_mult
    @query.gsub!(/[\t ]+of[\t ]+/, '*')
  end

  def x_to_mult
    @query.gsub!(/(#{@number_pattern}%?[\t ]*|[\(\)][\t ]*)x([\t ]*[\(\)]|[\t ]*#{@number_pattern}%?)/, '\1*\3')
  end

  def convert_percents
    # If we add/subtract a percent, we multiply/divide by 1 + (percent / 100)
    @query.gsub!(/(\+|\-)[\t ]*(#{@number_pattern})%/) do |match|
      if $1 == '+'
        "*#{($3.to_f / 100) + 1}"
      else
        "*#{1 - ($3.to_f / 100)}"
      end
    end
    
    # All other percents: just divide by 100
    @query.gsub!(/(#{@number_pattern})%/) {|num| ($1.to_f / 100).to_s }
  end

  # Returns an array of ranges for all functions
  def find_functions(query)
    function_ranges = []
    function_heading = /define[\t ]+([a-z][a-z0-9_]*).*\{/
    query.scan(function_heading) do |match|
      start_index = Regexp.last_match.begin(0)
      heading_length = Regexp.last_match.to_s.length
      
      open_braces = 0
      i = 0
      query[start_index + heading_length - 1, query.length].each_char do |char|
        open_braces += 1 if char == '{'
        open_braces -= 1 if char == '}'
        if open_braces == 0
          function_ranges << (start_index...start_index + i + heading_length)
          break
        end
        i += 1
      end
    end
    function_ranges
  end

  def index_in_function?(start_index)
    functions.each do |range|
      return true if range.include?(start_index)
    end
    false
  end

  def index_in_var_declaration?(start_index)
    variables.each do |range|
      return true if range.include?(start_index)
    end
    false
  end

  # Returns an array containing hashes representing the variables, containing the
  # name, value, and range of the variable
  # Note: doesn't include variables in a function
  def find_variables(query)
    variables = []
    variable_declaration = /
      (?:^|;|\n)        # match the start of a statement (semicolons and newlines
        [\t ]*             # separate statements)
        
      ([a-z][a-z0-9_]*) # match a variable name; must be lowercase and start with
        [\t ]*             # a letter, and can contain numbers and underscores
        
      (\+|-|\/|\*|)=    # find an equal sign, optionally with an operator prefix
        [\t ]*
        
      ([^;\n$]*)        # get the value of the variable, up until the end of the
                        # statement
    /x

    # Look for variable declarations
    query.scan(variable_declaration) do |match|
      start_index = Regexp.last_match.begin(0)
      length = Regexp.last_match.to_s.length
      
      variables << {
        :name => match[0],
        :value => match[2],
        :range => (start_index...start_index + length)
      } unless index_in_function?(start_index)
    end
    variables
  end

  def replace_variable(query, var, begin_pos)
    variable_pattern = /([^a-z0-9_])#{var[:name]}(?!\w)/

    query = query.gsub(variable_pattern) do |match|
      if index_in_var_declaration?($~.begin(0) + begin_pos) || index_in_function?($~.begin(0) + begin_pos)
        match
      elsif var[:value] =~ @number_pattern
        var[:value]
      else
        "(#{var[:value]})"
      end
    end

    query
  end

  # Replace instances of variables with the last defined value of that variable
  def replace_variables
    variables.each_with_index do |var, i|
      begin_pos = var[:range].last + 1
      if variables[i + 1]
        end_pos = variables[i + 1][:range].first
      else
        end_pos = @query.length
      end

      variables.first(i + 1).reverse_each do |current_var|
        next unless @query[begin_pos...end_pos]
        @query[begin_pos...end_pos] = replace_variable(@query[begin_pos...end_pos], current_var, begin_pos)
      end
    end
  end
end