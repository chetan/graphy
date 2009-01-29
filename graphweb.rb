#!/usr/bin/env ruby

# == Synopsis 
#   This is a sample description of the application.
#   Blah blah blah.
#
# == Examples
#   This command does blah blah blah.
#     graphweb.rb --file data/test
#
# == Usage 
#   graphweb.rb [options] --file [DATA.CSV]
#
#   For help use: graphweb.rb --help
#
# == Options
#   -h, --help          Displays help message
#   -V, --version       Display the version, then exit
#   -q, --quiet         Output as little as possible, overrides verbose
#   -v, --verbose       Verbose output
#   -f, --file [FILE]   CSV file containing data
#
# == Author
#   Chetan Sarva <chetan@pixelcop.net>
#
# == Copyright
#   Copyright (c) 2009 Chetan Sarva. Licensed under the MIT License:
#   http://www.opensource.org/licenses/mit-license.php


# TODO
# configurable columns
#   date and time in any column
#   date and time in different formats 
#   data from any column
# labels for columns to go in output
# input from stdin
# use out:csv instead of rendering in html source
# simple form for controlling out:csv query - range? etc
# detect header row in csv file

# DONE
# rollup each interval (take an average of values instead of dropping) aka rolling/moving average
# multiple datasets (multiple columns with data)
# "primary" dataset for applying std dev
# command line options
# pass filename for input

require 'optparse' 
require 'rdoc/usage'
require 'ostruct'
require 'date'
require 'pp'
require 'webrick'
include WEBrick


class GraphServlet < HTTPServlet::AbstractServlet

    def do_GET(req, res)
  
        res['Content-Type'] = 'text/html'
        
        datasets = DataSet.create
        
        body = []
        body << <<-EOF
<html>
  <head>
    <script type='text/javascript' src='http://www.google.com/jsapi'></script>
    <script type='text/javascript'>
      google.load('visualization', '1', {'packages':['annotatedtimeline']});
      google.setOnLoadCallback(drawChart);
      function drawChart() {
        var i;
        var data = new google.visualization.DataTable(
EOF
        body << datasets.to_js_table()
        body << ", 0.5);\n\n"

        body << <<-EOF
        var chart = new google.visualization.AnnotatedTimeLine(document.getElementById('chart_div'));
        chart.draw(data, {displayAnnotations: true});
      }
    </script>
  </head>

  <body>
    <div id='chart_div' style='width: 98%; height: 480px;'></div>
  </body>
</html>
EOF
    
        res.body = body.join
    
    end
       
end

# need this singleton so we can grab the data from inside our servlet
class DataSet
    
    attr_accessor :data, :num, :cols    

    private_class_method :new
    @@dataset = nil
    def self.create
        @@dataset = new if not @@dataset
        return @@dataset
    end
    
    def initialize
        @data = []
        @cols = []
        @num = 0
    end
    
    
#     {
#       cols: [{id: 'A', label: 'NEW A', type: 'string'},
#              {id: 'B', label: 'B-label', type: 'number'},
#              {id: 'C', label: 'C-label', type: 'date'}
#             ],
#       rows: [{c:[{v: 'a'}, {v: 1.0, f: 'One'}, {v: new Date(2008, 1, 28, 0, 31, 26), f: '2/28/08 12:31 AM'}]},
#              {c:[{v: 'b'}, {v: 2.0, f: 'Two'}, {v: new Date(2008, 2, 30, 0, 31, 26), f: '3/30/08 12:31 AM'}]},
#              {c:[{v: 'c'}, {v: 3.0, f: 'Three'}, {v: new Date(2008, 3, 30, 0, 31, 26), f: '4/30/08 12:31 AM'}]}
#             ]
#     }  
    
    def to_js_table
    
        buff = []
        
        buff << '{ '
        buff << 'cols: ['
        buff << "{id: 'date', label: 'Date/Time', type: 'datetime'}"
        @cols.each_with_index { |col,i|
            buff << ",{id: 'col_#{i}', label: '#{col}', type: 'number'}"
        }
        buff << "],"
        
        buff << 'rows: ['
        @data.each_with_index { |d,i|
            buff << "," if i > 0
            buff << sprintf("{c:[{v: new Date(%s)}", d[0] * 1000)
            (1..@num).each { |idx|
                buff << sprintf(",{v: %s}", d[idx])
            }
            buff << "]}"
        }
        buff << "] }"
        
        return buff.join
    
    end
    
    def to_csv
    
        buff = []
        
        buff << 'date'
        @cols.each { |col|
            buff << ',' + col[0]
        }
        buff << "\n"
        
        @data.each { |d|
            buff << sprintf("%s", d[0] * 1000)
            (1..@num).each { |idx|
                buff << sprintf(",%s", d[idx])
            }
            buff << "\n"
        }
        
        return buff.join()
    
    end

end

# variance & std dev swiped from 
# http://warrenseen.com/blog/2006/03/13/how-to-calculate-standard-deviation/

# calculate the variance of a population
# accepts: an array, the population
# returns: the variance
def variance(population)
    n = 0
    mean = 0.0
    s = 0.0
    population.each { |x|
        n = n + 1
        delta = x - mean
        mean = mean + (delta / n)
        s = s + delta * (x - mean)
    }
    # if you want to calculate std deviation
    # of a sample change this to "s / (n-1)"
    return s / n
end

# calculate the standard deviation of a population
# accepts: an array, the population
# returns: the standard deviation
def standard_deviation(population)
    Math.sqrt(variance(population))
end

def sum(population)
    return 0 if not population or population.empty?
    sum = 0
    population.each { |n| sum += n }
    return sum
end

def average(population) 
    return 0 if not population or population.empty?
    avg = sum(population) / population.length
end

# reduce dataset using intervals
def create_intervals(pop, interval)
    next_line = interval
    intervals = []
    pop.each { |d|
        if d[0] >= next_line then
            next_line = d[0] + interval
            intervals << d
        end
    }
    return intervals
end

# we could make this routine even more generic by not assuming any qualities of pop
# e.g., that in this case it is an array of arrays
# by using procs to do the actual rollups and window testing
def create_rolling_intervals(pop, interval)
    
    w_start = 0
    w_end = interval
    
    intervals = []
    window = []
    
    prc = Proc.new { |d, last|
        if window.length > 0 then
            last_val = window[-1]
            # rollup each data column
            r = [ last_val[0] ]
            (1..DataSet.create.num).each { |idx|
                r << average( window.collect { |n| n[idx] } )
            }
            intervals << r
        else
            last_val = d
        end        
        if not last then
            # start new one
            window = [ d ]
            w_start = last_val[0]
            w_end = last_val[0] + interval
        end
    }
    
    # 1 2 3 4 5 5 5 6 7 8
    pop.each { |d|
        if d[0] >= w_start and d[0] <= w_end then
            # within the current interval window
            window << d
        else
            # we've passed outside of the current interval window
            #   average the last window, and start a new one
            #p d
            prc.call(d, false)
            
        end
    }
    prc.call(nil, true)
    return intervals
end

def remove_outliers(data, pop, index)
    std_dev = standard_deviation(pop)
    outlier = average(pop) + (std_dev * 2)
    return data.delete_if { |d| d[index] >= outlier }
end

def massage_data(data, index, reduce_outliers = true)

    # remove outliers - anything more than 2 std deviations away
    pop = data.collect { |d| d[index] }
    data = remove_outliers(data, pop, index) if reduce_outliers
    
    # when dealing with multiple datasets, will want to change the scale to 0-100
    # for each set so it graphs nicely
    max = pop.max
    data.each { |d| 
        d[index] = d[index]  / max * 100 
    }
    
    return data

end

class Graphy

    # currently a file stream works best
    def load_data(stream)
    
        @datasets = DataSet.create
        
        # setup column info
        @datasets.cols = [ ['Page size', 'title1', 'text1'], ['Response time', 'title2', 'text2'] ]
        
        # load csv input
        all_lines = []
        stream.each_line { |line| all_lines << line.strip.split(/[,\t]/).map { |s| s.to_f } }
        if all_lines.length == 0 then
            puts "no data found!"
            exit
        end
        @datasets.num = all_lines[0].length - 1
        
        # sort by date (ascending)
        all_lines.sort! { |a,b| a[0] <=> b[0] }      
        
        @datasets.data = create_rolling_intervals(all_lines, 60)
        @datasets.data = massage_data(@datasets.data, 1)
        @datasets.data = massage_data(@datasets.data, 2)
    
    end

    def run
        
        puts ''
        puts 'Going to start server at http://localhost:2000/graph'
        puts ''
        
        s = HTTPServer.new( :Port => 2000, :AccessLog => [ ['/dev/null',AccessLog::COMMON_LOG_FORMAT] ] )
        s.mount("/graph", GraphServlet)
        trap("INT"){ s.shutdown }
        s.start
    
    end

end

class GraphyCli

    VERSION = '0.1'
    
    attr_reader :options

    def initialize(arguments, stdin)
        @arguments = arguments
        @stdin = stdin
        
        # Set defaults
        @options = OpenStruct.new
        @options.verbose = false
        @options.quiet = false
        
        @graphy = Graphy.new
        
    end

    # Parse options, check arguments, then process the command
    def run
                
        if parsed_options? && arguments_valid? 

            process_arguments
            process_command
            
        else
            output_usage
        end
            
    end
    
    protected
    
    def parsed_options?
        
        # Specify options
        opts = OptionParser.new 
        opts.on('-V', '--version')        { output_version ; exit 0 }
        opts.on('-h', '--help')           { output_help }
        opts.on('-v', '--verbose')        { @options.verbose = true }    
        opts.on('-q', '--quiet')          { @options.quiet = true }
        
        opts.on('-f', '--file [FILE]')           { |f| @options.file = f }
        
                    
        opts.parse!(@arguments) rescue return false
        
        process_options
        true            
    end

    # Performs post-parse processing on options
    def process_options
        @options.verbose = false if @options.quiet
    end
    
    def output_options
        puts "Options:\n"
        
        @options.marshal_dump.each do |name, val|                
            puts "    #{name} = #{val}"
        end
    end

    # True if required arguments were provided
    def arguments_valid?
        if not @options.file then
            return false
        end
        return true
    end
    
    # Setup the arguments
    def process_arguments
        # TO DO - place in local vars, etc
    end
    
    def process_command
        #process_standard_input # [Optional]
        @graphy.load_data(File.new(@options.file))
        @graphy.run        
        
    end

    def process_standard_input
        input = @stdin.read            
        # TO DO - process input
        
        # [Optional]
        #@stdin.each do |line| 
        #    # TO DO - process each line
        #end
    end
    
    def output_help
        output_version
        RDoc::usage() #exits app
    end
    
    def output_usage
        RDoc::usage('usage') # gets usage from comments above
    end
    
    def output_version
        puts "#{File.basename(__FILE__)} version #{VERSION}"
    end
    
end

# Create and run the application
app = GraphyCli.new(ARGV, STDIN)
app.run
