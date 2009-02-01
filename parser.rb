
require 'compiler'

prog = [:do,
  [:defun, :parse_quoted, [:c],
    [:while, [:and, [:ne, [:assign, :c, [:getchar]], -1], [:ne, :c, 34]], [:do,
        [:putchar, :c]
      ]
    ]
  ],
  [:defun, :parse, [:c,:sep], 
    [:while, [:and, [:ne, [:assign, :c, [:getchar]], -1], [:ne, :c, 41]], [:do,
        [:if, [:eq,:c, 40], [:do,
            [:printf, "["],
            [:parse,0,0],
            [:printf, "]"],
            [:assign, :sep, 1]
          ],
          [:if, [:eq, :c, 34], [:do,
              [:putchar,34],
              [:parse_quoted,0],
              [:putchar,34],
              [:assign, :sep, 1]
            ],
            [:do,
              [:if, [:and, [:isspace, :c], :sep], [:do,
                  [:printf, ","],
                  [:assign, :sep, 0]
                ]
              ],
              [:if, [:and, [:isalnum, :c], [:not, :sep]], [:do,
                    [:assign, :sep, 1],
                    [:if, [:not, [:isdigit, :c]],[:printf,":"]]
                ]
              ],
              [:putchar, :c]
            ]
          ]
        ]
      ]
    ]
  ],
  [:puts, "require 'compiler'\\n"],
  [:puts, "prog = [:do,"],
  [:parse, 0,0],
  [:puts, "]\\n"],
  [:puts, "Compiler.new.compile(prog)"]
]

Compiler.new.compile(prog)

