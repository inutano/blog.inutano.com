import * as React from "react"
import { Link, HeadFC, PageProps } from "gatsby"
import { graphql } from 'gatsby'
import { compiler } from 'markdown-to-jsx';
import "./styles.sass"

export const query = graphql`
  query {
    allMdx(sort: {frontmatter: {datePublished: DESC}}) {
      nodes {
        id
        frontmatter {
          title
          datePublished(formatString: "YYYYMMDD")
        }
        internal {
          contentFilePath
        }
        body
      }
    }
  }
`

const IndexPage: React.FC<PageProps> = ({data}) => {
  return (
    <main>
      <header>
        <Link to='https://blog.inutano.com'>
          <h1 class='blogTitle'>blog.inutano.com</h1>
        </Link>
      </header>
      <article>
        {data.allMdx.nodes.map(node => (
          <section>
            <h2 id={node.frontmatter.datePublished}>{node.frontmatter.title}</h2>
            {compiler(node.body)}
          </section>
        ))}
      </article>
    </main>
  )
}

export default IndexPage

export const Head: HeadFC = () => {
  return (
    <title>
      blog.inutano.com
    </title>
  )
}
