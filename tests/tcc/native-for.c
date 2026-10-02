int main(void) { int sum=0; for (int i=0;i<4;i++) { for(int j=0;j<5;j++) { if(j==2) continue; sum+=i+j; } } return sum-56; }
