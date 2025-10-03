$input = [
  :do,
  [:defm, :test, [], [
      [:assign, :a, [:sexp, 3]],
      [:callm, [:array, [:sexp, 3], [:sexp, 5], [:sexp, 7]], :each, [],
        [:proc, [:a], [
          [:callm, [:array, [:sexp, 9], [:sexp, 11], [:sexp, 13]], :each, [],
            [:proc, [:b], [
              [:call, :p, [:a]]
            ]]
          ]]
        ]],
      [:call, :p, [:a]]]
  ],
  :test
]

# A is aliased, so *outer* a should not be taken from env
#
# TODO: Difference is now alloc_env call and assigning __closure__
$output = [:do,
 [:defm,
  :test,
  [],
  [:let, [:__env__, :__tmp_proc],
   [:sexp, [:assign, :__env__, [:call, :__alloc_env, 4]]],
   [:assign, [:index, :__env__, 2], :__closure__],
   [:assign, :a, [:sexp, 3]],
   [:callm,
    [:array, [:sexp, 3], [:sexp, 5], [:sexp, 7]],
    :each,
    [],
    [:do,
     [:assign, [:index, :__env__, 0], [:stackframe]],
     [:assign,
      :__tmp_proc,
      [:defun,
       "__lambda_L0",
       [:self, :__closure__, :__env__, [:a, :default, :nil]],
       [:assign, [:index, :__env__, 1], :a],
       [:let,
        [],
        [:callm,
         [:array, [:sexp, 9], [:sexp, 11], [:sexp, 13]],
         :each, [],
         [:do,
          [:assign, [:index, :__env__, 0], [:stackframe]],
          [:assign, :__tmp_proc,
           [:defun,
            "__lambda_L1",
            [:self, :__closure__, :__env__, [:b, :default, :nil]],
            [:let, [], [:call, :p, [[:index, :__env__, 1]]]]]],
          [:sexp,
           [:call, :__new_proc, [:__tmp_proc, :__env__, :self, 1]]]]]]]],
     [:sexp, [:call, :__new_proc, [:__tmp_proc, :__env__, :self, 1]]]]],
   [:call, :p, [:a]]]],
 :test]
