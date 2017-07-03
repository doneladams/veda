mkdir chunk-io

zip -v -r ./chunk-io/logs.zip logs

cd chunk-io

count=$(git ls-files -o | wc -l)
echo "COUNT=$count"
git ls-files -o

echo ">>>>>>>>> CONTAINERS LOG FILES <<<<<<<<<<<<"

echo "@0"

for (( i=1; i<="$count";i++ ))

do

echo "@1"

file=$(echo $(git ls-files -o | sed "${i}q;d"))

echo "FILE=$file"

cat $file | curl -sT - chunk.io

done

echo " >>>>> testsummary log file <<<< "

cat testsummary.log | curl -sT - chunk.io
