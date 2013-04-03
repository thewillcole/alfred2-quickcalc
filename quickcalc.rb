require 'shellwords'

class QuickCalc
  # Adds commas as a thousands separator
  # TODO: Support other locales
  def self.format_number(num)
    num_parts = num.to_s.split('.')
    formatted_number = num_parts.first.reverse.gsub(/...(?=.)/,'\&,').reverse
    formatted_number += '.' + num_parts[1] if num_parts.length > 1
    formatted_number
  end

  # Basically just converts a float to an int if it ends in .0
  # ...I'm bad at naming things.
  def self.remove_trailing_zero(float)
    if float - float.to_i == 0
      float.to_i
    else
      float
    end
  end

  def initialize(query, functions_file, custom_file)
    @query = query
    @number_pattern = /[-+]?([0-9]*\.[0-9]+|[0-9]+)/

    f = File.open(custom_file, 'r')
    custom = f.read
    f.close

    f = File.open(functions_file, 'r')
    defaults = f.read
    f.close

    @query = self.balance_parentheses(@query)
    @query = @query.strip
    @query = self.remove_trailing_operators(@query)

    @query = custom << "\n" << @query

    @query = self.convert_thousands_suffixes(@query)
    @query = self.replace_variables(@query)
    @query = self.of_to_mult(@query)
    @query = self.remove_superfluous_characters(@query)
    @query = self.convert_percents(@query)

    @query = @query.gsub('π', 'pi')
    @query = @query.gsub('**', '^')

    @query = defaults << "\n" << @query
  end

  def calculate
    `echo #{Shellwords.escape(@query)} | bc -l 2>&1`.strip
  end

  # Auto-closes parentheses so we can get immediate results.
  # If we find a closing paren, but we can't find any unmatched open parens, add
  # an open paren to the beginning of the expression (either the beginning of
  # the query, or after the last semicolon (bc doesn't like variable definitions
  # being wrapped in parens)). Once we're done, add any necessary closing parens
  # to the end.
  def balance_parentheses(query)
    query = query.dup
    num_open = 0
    num_closed = 0
    query_start = (query.rindex(';') || -1) + 1

    query.each_char do |char|
      if char == '('
        num_open += 1
      elsif char == ')'
        num_closed += 1
        if num_closed > num_open
          query = query.insert(query_start, '(')
          num_open += 1
        end
      end
    end

    if num_open > num_closed
      query << ')' * (num_open - num_closed)
    else
      query
    end
  end

  # Prevents it from showing 0 immediately after typing a new operator
  def remove_trailing_operators(query)
    operators = %w[+ - / * ^ = (]
    last_char = query[query.length - 1, 1]

    if operators.include?(last_char)
      self.remove_trailing_operators(query.chop)
    else
      query
    end
  end

  def remove_superfluous_characters(query)
    # Remove spaces between numbers
    query.gsub(/(\d+)\s+(\d+)/, '\1\2')
    # Removes commas that aren't followed by a space. If you want to separate
    # function arguments, press space after the comma.
    query = query.gsub(/,(?! )/, '')
    # Remove some common currency signs
    query = query.gsub('$', '').gsub('£', '').gsub('€', '')
    # Remove underscores after a number so they can be used as a thousands
    # separator, but still work in variable/function names.
    query = query.gsub(/(\d)_/, '\1')
  end

  def convert_thousands_suffixes(query)
    query = query.gsub(/(#{@number_pattern})(k|m|b| thousand| million| billion)/) do |match|
      if $3 == 'k' || $3 == ' thousand'
        "#{$2}*1000"
      elsif $3 == 'm' || $3 == ' million'
        "#{$2}*1000000"
      elsif $3 == 'b' || $3 == ' billion'
        "#{$2}*1000000000"
      end
    end
    query
  end

  # TODO: Make this work with expressions other than integer literals
  # This attempts the fix the issue with scale affecting modulus by using a bc
  # function instead. Only works with integer literals right now.
  # def convert_mod(query)
  #   query = query.gsub(/\b(\w|\d+)\s+mod\s+(\w|\d+)\b/, 'mod(\1, \2)')
  #   query = query.gsub(/\b(\d+)mod(\d+)\b/, 'mod(\1, \2)')
  # end

  # Make 'of' an alias of '*'
  def of_to_mult(query)
    query.gsub(/\s+of\s+/, '*')
  end

  def convert_percents(query)
    # If we add/subtract a percent, we multiply/divide by 1 + (percent / 100)
    query = query.gsub(/(\+|\-)\s*(#{@number_pattern})%/) do |match|
      if $1 == '+'
        "*#{($3.to_f / 100) + 1}"
      else
        "*#{1 - ($3.to_f / 100)}"
      end
    end
    
    # All other percents: just divide by 100
    query = query.gsub(/(#{@number_pattern})%/) {|num| ($1.to_f / 100).to_s }
  end

  # Returns an array of ranges for all functions
  def find_functions(query)
    function_ranges = []
    function_heading = /define\s+([a-z][a-z0-9_]*).*\{/
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

  # Returns an array containing hashes representing the variables, containing the
  # name, value, and range of the variable
  # Note: doesn't include variables in a function
  def find_variables(query)
    variables = []
    function_ranges = self.find_functions(query)
    variable_declaration = /
      (?:^|;|\n)        # match the start of a statement (semicolons and newlines
        \s*             # separate statements)
        
      ([a-z][a-z0-9_]*) # match a variable name; must be lowercase and start with
        \s*             # a letter, and can contain numbers and underscores
        
      (\+|-|\/|\*|)=    # find an equal sign, optionally with an operator prefix
        \s*
        
      ([^;\n$]*)        # get the value of the variable, up until the end of the
                        # statement
    /x

    # Look for variable declarations
    query.scan(variable_declaration) do |match|
      start_index = Regexp.last_match.begin(0)
      length = Regexp.last_match.to_s.length
      
      is_var_in_function = false
      function_ranges.each do |range|
        if range.include?(start_index)
          is_var_in_function = true
          break
        end
      end
      
      variables << {
        :name => match[0],
        :value => match[2],
        :range => (start_index...start_index + length)
      } unless is_var_in_function
    end
    variables
  end

  def replace_variables(query)
    query = query.dup
    variables = self.find_variables(query)
    function_ranges = self.find_functions(query)
    
    return query if variables.length == 0
    
    variables.each_with_index do |var, i|
      begin_pos = var[:range].last + 1
      if variables[i + 1]
        end_pos = variables[i + 1][:range].first
      else
        end_pos = query.length
      end
      
      variables.first(i + 1).reverse_each do |current_var|
        next unless query[begin_pos...end_pos]
        query[begin_pos...end_pos] = query[begin_pos...end_pos].gsub(/([^a-z0-9_])#{current_var[:name]}(?!\w)/) do |match|
          last_match = Regexp.last_match
          if current_var[:value] =~ /[-+]?([0-9]*\.[0-9]+|[0-9]+)%?/
            num = current_var[:value]
          else
            num = "(#{current_var[:value]})"
          end
          val = "#{last_match[1]}#{num}"
          function_ranges.each do |range|
            if range.include?(last_match.begin(0) + begin_pos)
              val = match
              break
            end
          end
          val
        end
      end
    end
    query
  end
end