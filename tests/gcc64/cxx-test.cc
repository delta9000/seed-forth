#include <iostream>
#include <vector>
#include <map>
#include <string>
#include <algorithm>
#include <stdexcept>
#include <memory>
#include <sstream>
struct B { virtual ~B(){} virtual int f() const = 0; };
struct D : B { int v; D(int x):v(x){} int f() const { return v*2; } };
template<class T> T sum(const std::vector<T>& v){ T s = T(); for (size_t i=0;i<v.size();++i) s += v[i]; return s; }
int main() {
  int fails = 0;
  std::vector<int> v; for (int i = 10; i > 0; --i) v.push_back(i);
  std::sort(v.begin(), v.end()); if (v[0] != 1 || sum(v) != 55) { std::cout << "FAIL sort/sum\n"; fails++; }
  std::map<std::string,int> m; m["b"]=2; m["a"]=1; if (m.begin()->first != "a") { std::cout << "FAIL map\n"; fails++; }
  try { throw std::runtime_error("boom"); } catch (const std::exception& e) { if (std::string(e.what()) != "boom") fails++; }
  try { std::vector<int> e; e.at(5); fails++; } catch (const std::out_of_range&) {}
  std::auto_ptr<B> p(new D(21)); if (p->f() != 42) { std::cout << "FAIL virtual\n"; fails++; }
  std::ostringstream os; os << 3.5 << " " << 42 << " " << std::hex << 255; if (os.str() != "3.5 42 ff") { std::cout << "FAIL ostringstream: " << os.str() << "\n"; fails++; }
  std::cout << (fails ? "FAILED" : "PASSED") << ": C++ test, " << fails << " failures" << std::endl;
  return fails != 0;
}
