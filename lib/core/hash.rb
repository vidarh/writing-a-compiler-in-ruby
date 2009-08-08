
class Hash
  def [] index
    %s(printf "Hash#[]: %d on %p\n" index self)
  end
end
