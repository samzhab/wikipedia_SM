## Wikipedia Scholarly Article Citations Semantic Manipulation

available tasks
* extract page_id and id + serialize wikipedia scholarly articles using dataset from https://figshare.com/articles/Wikipedia_Scholarly_Article_Citations/1299540 and save as n-triples.

eg. < http://en.wikipedia.org/wiki?curid=972037 > < http://lod.openaire.eu/vocab/resOriginalID > "1576073459" .

* access https://api.crossref.org/v1/works/, extract paper title for dois mentioned in wikipedia scholarly articles then serialize doi has:title "title" triples as nt and save.

usage with rvm:
* place tsv files in folder named tsv_files in working directory
* create a folder named nt_files in working directory
* create a gemset
`$ rvm gemset create <gemset>`
* use created gemset
`$ rvm <ruby version>@<gemset>`
* install bundler gem
`$ gem install bundler`
* install necessary gems
`$ bundle`
* make script executable
`$ chmod +x <script_name.rb>`
* run script
`$ ./<script_name.rb>`
