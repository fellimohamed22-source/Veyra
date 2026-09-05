package com.veyra;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.core.type.filter.AnnotationTypeFilter;
import org.springframework.web.bind.annotation.*;

import java.lang.reflect.Method;
import java.util.*;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.assertTrue;

class RouteCollisionTest {
  private static final Pattern PATH_VARIABLE=Pattern.compile("\\{[^/}]+}");

  @Test
  void restRoutesMustBeUnique() throws Exception {
    var scanner=new ClassPathScanningCandidateComponentProvider(false);
    scanner.addIncludeFilter(new AnnotationTypeFilter(RestController.class));

    Map<String,List<String>> owners=new TreeMap<>();
    for(BeanDefinition bean:scanner.findCandidateComponents("com.veyra")){
      Class<?> type=Class.forName(Objects.requireNonNull(bean.getBeanClassName()));
      List<String> bases=paths(type.getAnnotation(RequestMapping.class));
      if(bases.isEmpty()) bases=List.of("");

      for(Method method:type.getDeclaredMethods()){
        for(Route route:routes(method)){
          for(String base:bases){
            for(String sub:route.paths()){
              String key=route.httpMethod()+" "+canonical(base,sub);
              owners.computeIfAbsent(key,k->new ArrayList<>())
                  .add(type.getName()+"#"+method.getName());
            }
          }
        }
      }
    }

    List<String> collisions=owners.entrySet().stream()
        .filter(e->e.getValue().size()>1)
        .map(e->e.getKey()+" -> "+String.join(", ",e.getValue()))
        .toList();

    assertTrue(collisions.isEmpty(),"Duplicate REST mappings:\n"+String.join("\n",collisions));
  }

  private static List<Route> routes(Method method){
    List<Route> routes=new ArrayList<>();
    GetMapping get=method.getAnnotation(GetMapping.class);
    if(get!=null) routes.add(new Route("GET",paths(get.path(),get.value())));
    PostMapping post=method.getAnnotation(PostMapping.class);
    if(post!=null) routes.add(new Route("POST",paths(post.path(),post.value())));
    PutMapping put=method.getAnnotation(PutMapping.class);
    if(put!=null) routes.add(new Route("PUT",paths(put.path(),put.value())));
    DeleteMapping delete=method.getAnnotation(DeleteMapping.class);
    if(delete!=null) routes.add(new Route("DELETE",paths(delete.path(),delete.value())));
    PatchMapping patch=method.getAnnotation(PatchMapping.class);
    if(patch!=null) routes.add(new Route("PATCH",paths(patch.path(),patch.value())));
    RequestMapping request=method.getAnnotation(RequestMapping.class);
    if(request!=null){
      List<String> ps=paths(request);
      if(ps.isEmpty()) ps=List.of("");
      if(request.method().length==0) routes.add(new Route("ANY",ps));
      else for(RequestMethod http:request.method()) routes.add(new Route(http.name(),ps));
    }
    return routes;
  }

  private static List<String> paths(RequestMapping mapping){
    if(mapping==null) return List.of();
    return paths(mapping.path(),mapping.value());
  }

  private static List<String> paths(String[] path,String[] value){
    LinkedHashSet<String> result=new LinkedHashSet<>();
    result.addAll(Arrays.asList(path));
    result.addAll(Arrays.asList(value));
    result.remove("");
    return new ArrayList<>(result);
  }

  private static String canonical(String base,String sub){
    String combined=(base+"/"+sub).replaceAll("/+","/");
    if(!combined.startsWith("/")) combined="/"+combined;
    if(combined.length()>1&&combined.endsWith("/")) combined=combined.substring(0,combined.length()-1);
    return PATH_VARIABLE.matcher(combined).replaceAll("{}");
  }

  private record Route(String httpMethod,List<String> paths){
    Route {
      if(paths.isEmpty()) paths=List.of("");
    }
  }
}
